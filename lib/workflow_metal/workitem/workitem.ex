defmodule WorkflowMetal.Workitem.Workitem do
  @moduledoc """
  A `GenStateMachine` to run a workitem.

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
  """

  require Logger

  use GenStateMachine,
    callback_mode: [:handle_event_function, :state_enter],
    restart: :temporary

  alias WorkflowMetal.Storage.Schema

  defstruct [
    :application,
    :workitem_schema
  ]

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Supervisor.workflow_identifier()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()
  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()
  @type workitem_output :: WorkflowMetal.Storage.Schema.Workitem.output()

  @type options :: [
          name: term(),
          workitem_schema: workitem_schema
        ]

  @doc false
  @spec start_link(workflow_identifier, options) :: :gen_statem.start_ret()
  def start_link(workflow_identifier, options) do
    name = Keyword.fetch!(options, :name)
    workitem_schema = Keyword.fetch!(options, :workitem_schema)

    GenStateMachine.start_link(
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
  @spec complete(:gen_statem.server_ref(), workitem_output) ::
          :ok | {:error, :workitem_not_available}
  def complete(workitem_server, output) do
    GenStateMachine.call(workitem_server, {:complete, output})
  end

  @doc """
  Abandon a workitem.
  """
  @spec abandon(:gen_statem.server_ref()) :: :ok
  def abandon(workitem_server) do
    GenStateMachine.cast(workitem_server, :abandon)
  end

  # callbacks

  @impl GenStateMachine
  def init({{application, _workflow_id}, workitem_schema}) do
    %{
      state: state
    } = workitem_schema

    if state in [:completed, :abandoned] do
      {:stop, :normal}
    else
      {
        :ok,
        state,
        %__MODULE__{
          application: application,
          workitem_schema: workitem_schema
        }
      }
    end
  end

  @impl GenStateMachine
  def handle_event(:enter, state, state, %__MODULE__{}) do
    case state do
      :created ->
        {
          :keep_state_and_data,
          {:state_timeout, 0, :start_at_created}
        }

      _ ->
        :keep_state_and_data
    end
  end

  @impl GenStateMachine
  def handle_event(:enter, old_state, state, %__MODULE__{} = data) do
    case {old_state, state} do
      {:created, :started} ->
        Logger.debug(fn -> "#{describe(data)} start executing." end)

        {:ok, data} = update_workitem(:started, data)
        {:keep_state, data}

      {:started, :completed} ->
        Logger.debug(fn -> "#{describe(data)} complete the execution." end)

        {:keep_state, data}

      {_from, :abandoned} ->
        Logger.debug(fn -> "#{describe(data)} has been abandoned." end)

        {:ok, data} = do_abandon(data)
        {:keep_state, data}
    end
  end

  @impl GenStateMachine
  def handle_event(:state_timeout, :start_at_created, :created, %__MODULE__{}) do
    {:keep_state_and_data, [{:next_event, :cast, :start}]}
  end

  @impl GenStateMachine
  def handle_event(:internal, :stop, _state, %__MODULE__{} = data) do
    {:stop, :normal, data}
  end

  @impl GenStateMachine
  def handle_event(:cast, :start, :created, %__MODULE__{} = data) do
    case do_execute(data) do
      {:ok, :started, data} ->
        {:next_state, :started, data}

      {:ok, {:completed, workitem_output}, data} ->
        {
          :next_state,
          :started,
          data,
          {:next_event, :cast, {:complete, workitem_output}}
        }

      {:ok, :abandoned, data} ->
        {:next_state, :abandoned, data}
    end
  end

  @impl GenStateMachine
  def handle_event(:cast, {:complete, output}, :started, %__MODULE__{} = data) do
    {:ok, data} = do_complete(output, data)

    {
      :next_state,
      :completed,
      data,
      {:next_event, :internal, :stop}
    }
  end

  @impl GenStateMachine
  def handle_event(:cast, :abandon, state, %__MODULE__{} = data)
      when state not in [:abandoned, :completed] do
    {
      :next_state,
      :abandoned,
      data,
      {:next_event, :internal, :stop}
    }
  end

  @impl GenStateMachine
  def handle_event(:cast, :abandon, _state, %__MODULE__{}) do
    :keep_state_and_data
  end

  @impl GenStateMachine
  def handle_event(:cast, _event_content, _state, %__MODULE__{}) do
    :keep_state_and_data
  end

  @impl GenStateMachine
  def handle_event({:call, from}, {:complete, output}, :started, %__MODULE__{} = data) do
    {:ok, data} = do_complete(output, data)

    {
      :next_state,
      :completed,
      data,
      [
        {:reply, from, :ok},
        {:next_event, :internal, :stop}
      ]
    }
  end

  @impl GenStateMachine
  def handle_event({:call, from}, _event_content, _state, %__MODULE__{}) do
    {:keep_state_and_data, {:reply, from, {:error, :workitem_not_available}}}
  end

  @impl GenStateMachine
  def format_status(_reason, [_pdict, state, data]) do
    {:state, %{current_state: state, data: data}}
  end

  defp update_workitem(state_and_options, %__MODULE__{} = data) do
    %{
      application: application,
      workitem_schema: workitem_schema
    } = data

    {:ok, workitem_schema} =
      WorkflowMetal.Storage.update_workitem(
        application,
        workitem_schema.id,
        state_and_options
      )

    {:ok, %{data | workitem_schema: workitem_schema}}
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

  defp do_complete(output, %__MODULE__{} = data) do
    {
      :ok,
      %{
        workitem_schema: workitem_schema
      } = data
    } = update_workitem({:completed, output}, data)

    :ok =
      WorkflowMetal.Task.Task.complete_workitem(
        task_server(data),
        workitem_schema.id
      )

    {:ok, data}
  end

  defp do_abandon(%__MODULE__{} = data) do
    {
      :ok,
      %{
        workitem_schema: %Schema.Workitem{
          id: workitem_id
        }
      }
    } = update_workitem(:abandoned, data)

    :ok =
      WorkflowMetal.Task.Task.abandon_workitem(
        task_server(data),
        workitem_id
      )

    {:ok, data}
  end

  defp task_server(%__MODULE__{} = data) do
    %{
      application: application,
      workitem_schema: %Schema.Workitem{
        workflow_id: workflow_id,
        case_id: case_id,
        transition_id: transition_id,
        task_id: task_id
      }
    } = data

    WorkflowMetal.Task.Task.via_name(application, {workflow_id, transition_id, case_id, task_id})
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

    "Workitem<#{workitem_id}@#{workflow_id}.#{transition_id}.#{case_id}.#{task_id}>"
  end
end
