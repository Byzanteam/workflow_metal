defmodule WorkflowMetal.Workitem.Workitem do
  @moduledoc """
  A `GenServer` to run a workitem.

  ## Flow

  The workitem starts to execute, when the workitem is created.

  If the executor returns `:started`,
  you can call `:complete` with the `workitem_output` to complete the workitem manually(asynchronously).

  If the executor returns `{:completed, workitem_output}`,
  the workitem is completed immediately.

  The task can abandon the workitem when needed.

  ## State

  ```
  created+-------->started+------->completed
      +               +
      |               |
      |               v
      +---------->abandoned
  ```

  ## Restore

  Restore itself only.
  """

  use GenServer, restart: :transient
  use TypedStruct

  alias WorkflowMetal.Storage.Schema

  require Logger

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Supervisor.workflow_identifier()

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()

  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()

  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()
  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()
  @type workitem_output :: WorkflowMetal.Storage.Schema.Workitem.output()

  typedstruct do
    field :application, application()
    field :state, WorkflowMetal.Storage.Schema.Workitem.state()
    field :workitem_schema, workitem_schema()
  end

  @type options :: [
          name: term(),
          workitem_schema: workitem_schema
        ]

  @type on_complete :: :ok | {:error, :workitem_not_available}
  @type on_abandon :: :ok

  @doc false
  @spec start_link(workflow_identifier, options) :: :gen_statem.start_ret()
  def start_link(workflow_identifier, options) do
    name = Keyword.fetch!(options, :name)
    workitem_schema = Keyword.fetch!(options, :workitem_schema)

    GenServer.start_link(
      __MODULE__,
      {workflow_identifier, workitem_schema},
      name: name
    )
  end

  @doc false
  @spec name({workflow_id, transition_id, case_id, workitem_id}) :: term()
  def name({workflow_id, transition_id, case_id, workitem_id}) do
    {__MODULE__, {workflow_id, transition_id, case_id, workitem_id}}
  end

  @doc false
  @spec name(workitem_schema) :: term()
  def name(%Schema.Workitem{} = workitem_schema) do
    %{
      id: workitem_id,
      workflow_id: workflow_id,
      case_id: case_id,
      transition_id: transition_id
    } = workitem_schema

    name({workflow_id, transition_id, case_id, workitem_id})
  end

  @doc false
  @spec via_name(application, {workflow_id, case_id, transition_id, workitem_id}) :: term()
  def via_name(application, {workflow_id, case_id, transition_id, workitem_id}) do
    WorkflowMetal.Registration.via_tuple(
      application,
      name({workflow_id, case_id, transition_id, workitem_id})
    )
  end

  @doc false
  @spec via_name(application, workitem_schema) :: term()
  def via_name(application, %Schema.Workitem{} = workitem_schema) do
    WorkflowMetal.Registration.via_tuple(
      application,
      name(workitem_schema)
    )
  end

  @doc """
  Complete a workitem.
  """
  @spec complete(:gen_statem.server_ref(), workitem_output) :: on_complete
  def complete(workitem_server, output) do
    GenServer.call(workitem_server, {:complete, output})
  end

  @doc """
  Abandon a workitem.
  """
  @spec abandon(:gen_statem.server_ref()) :: :ok
  def abandon(workitem_server) do
    GenServer.cast(workitem_server, :abandon)
  end

  # callbacks

  @impl GenServer
  def init({{application, _workflow_id}, workitem_schema}) do
    case workitem_schema.state do
      :created ->
        {
          :ok,
          %__MODULE__{
            application: application,
            state: :created,
            workitem_schema: workitem_schema
          },
          {:continue, :execute_on_created}
        }

      :started ->
        {
          :ok,
          %__MODULE__{
            application: application,
            state: :started,
            workitem_schema: workitem_schema
          },
          get_timeout(application)
        }

      state when state in [:completed, :abandoned] ->
        {:stop, :workitem_not_available}
    end
  end

  @impl GenServer
  def handle_continue(:execute_on_created, %{state: :created} = data) do
    Logger.debug("#{describe(data)} start executing.")

    case do_execute(data) do
      {:ok, :started, data} ->
        data = update_workitem(%{state: :started}, data)

        {:noreply, data, get_timeout(data.application)}

      {:ok, {:completed, workitem_output}, data} ->
        {:noreply, %{data | state: :started}, {:continue, {:complete, workitem_output}}}

      {:ok, :abandoned, data} ->
        data = update_workitem(%{state: :abandoned}, data)

        {:noreply, data, get_timeout(data.application)}
    end
  end

  @impl GenServer
  def handle_continue({:complete, output}, %{state: :started} = data) do
    data = do_complete(data, output)

    {:noreply, data, {:continue, :stop_server}}
  end

  @impl GenServer
  def handle_continue(:stop_server, data) do
    {:stop, :normal, data}
  end

  @impl GenServer
  def handle_call({:complete, output}, _from, %{state: :started} = data) do
    data = do_complete(data, output)

    {:reply, :ok, data, {:continue, :stop_server}}
  end

  @impl GenServer
  def handle_call({:complete, _output}, _from, data) do
    {:reply, {:error, :workitem_not_available}, data, {:continue, :stop_server}}
  end

  @impl GenServer
  def handle_cast(:abandon, %{state: state} = data) when state not in [:abandoned, :completed] do
    data = do_abanodn(data)

    {:noreply, data, {:continue, :stop_server}}
  end

  @impl GenServer
  def handle_cast(:abandon, data) do
    {:noreply, data, {:continue, :stop_server}}
  end

  @impl GenServer
  def handle_info(:timeout, %__MODULE__{} = data) do
    Logger.debug(describe(data) <> " stopping due to inactivity timeout")

    {:stop, :normal, data}
  end

  @spec update_workitem(map(), t()) :: t()
  defp update_workitem(params, %__MODULE__{} = data) do
    %{
      application: application,
      workitem_schema: workitem_schema
    } = data

    {:ok, workitem_schema} =
      WorkflowMetal.Storage.update_workitem(
        application,
        workitem_schema.id,
        params
      )

    new_data = %{data | workitem_schema: workitem_schema, state: workitem_schema.state}

    if new_data.state != data.state do
      update_workitem_in_task_server(new_data)
    end

    new_data
  end

  defp do_execute(%__MODULE__{} = data) do
    %{
      application: application,
      workitem_schema:
        %Schema.Workitem{
          transition_id: transition_id
        } = workitem_schema
    } = data

    {
      :ok,
      %{
        executor: executor,
        executor_params: executor_params
      }
    } = WorkflowMetal.Storage.fetch_transition(application, transition_id)

    case executor.execute(
           workitem_schema,
           executor_params: executor_params,
           application: application
         ) do
      :started ->
        {:ok, :started, data}

      {:completed, workitem_output} ->
        {:ok, {:completed, workitem_output}, data}

      :abandoned ->
        {:ok, :abandoned, data}
    end
  end

  @spec do_complete(t(), output :: term()) :: t()
  defp do_complete(%__MODULE__{} = data, output) do
    data = update_workitem(%{state: :completed, output: output}, data)

    Logger.debug("#{describe(data)} complete the execution.")

    data
  end

  @spec do_abanodn(t()) :: t()
  defp do_abanodn(%__MODULE__{} = data) do
    %{
      application: application,
      workitem_schema:
        %Schema.Workitem{
          transition_id: transition_id
        } = workitem_schema
    } = data

    {
      :ok,
      %{
        executor: executor,
        executor_params: executor_params
      }
    } = WorkflowMetal.Storage.fetch_transition(application, transition_id)

    executor.abandon(
      workitem_schema,
      executor_params: executor_params,
      application: application
    )

    Logger.debug("#{describe(data)} has been abandoned from #{data.state}.")

    new_data = %{data | state: :abandoned}

    update_workitem(%{state: :abandoned}, new_data)
  end

  defp update_workitem_in_task_server(%__MODULE__{} = data) do
    %{
      application: application,
      workitem_schema:
        %Schema.Workitem{
          task_id: task_id
        } = workitem_schema
    } = data

    :ok =
      WorkflowMetal.Task.Supervisor.update_workitem(
        application,
        task_id,
        workitem_schema
      )

    {:ok, data}
  end

  defp get_timeout(application) do
    application
    |> WorkflowMetal.Application.Config.get(:case)
    |> Kernel.||([])
    |> Keyword.get(:lifespan_timeout, :timer.seconds(30))
  end

  defp describe(%__MODULE__{} = data) do
    %{
      workitem_schema: %Schema.Workitem{
        id: workitem_id,
        workflow_id: workflow_id,
        case_id: case_id,
        task_id: task_id,
        transition_id: transition_id
      }
    } = data

    "[#{inspect(__MODULE__)}] Workitem<#{workitem_id}@#{task_id}.#{case_id}##{transition_id}.#{workflow_id}>"
  end
end
