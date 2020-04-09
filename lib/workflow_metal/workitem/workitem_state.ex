defmodule WorkflowMetal.Workitem.WorkitemState do
  @moduledoc """
  A `GenStateMachine` to run a workitem.
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
  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()
  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()
  @type workitem_output :: WorkflowMetal.Storage.Schema.Workitem.output()

  @type error :: term()
  @type options :: [
          name: term(),
          workitem_schema: workitem_schema
        ]

  @spec start_link(workflow_identifier, options) :: GenServer.on_start()
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
  @spec name({workflow_id, case_id, transition_id, workitem_id}) :: term()
  def name({workflow_id, case_id, transition_id, workitem_id}) do
    {__MODULE__, {workflow_id, case_id, transition_id, workitem_id}}
  end

  @doc false
  @spec via_name(application, {workflow_id, case_id, transition_id, workitem_id}) :: term()
  def via_name(application, {workflow_id, case_id, transition_id, workitem_id}) do
    WorkflowMetal.Registration.via_tuple(
      application,
      name({workflow_id, case_id, transition_id, workitem_id})
    )
  end

  @doc """
  Complete a workitem.
  """
  @spec complete(GenServer.server(), workitem_output) ::
          :ok | {:error, :workitem_not_available}
  def complete(workitem_server, output) do
    GenStateMachine.call(workitem_server, {:complete, output})
  end

  @doc """
  Abandon a workitem.
  """
  @spec abandon(GenServer.server()) :: :ok
  def abandon(workitem_server) do
    GenStateMachine.cast(workitem_server, :abandon)
  end

  # callbacks

  @impl GenStateMachine
  def init({{application, _workflow_id}, workitem_schema}) do
    %{
      state: state
    } = workitem_schema

    cond do
      state in [:completed, :abandoned] ->
        {:stop, :normal}

      true ->
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
  def handle_event(:enter, old_state, state, %__MODULE__{} = data) do
    case {old_state, state} do
      {:created, :created} ->
        {
          :keep_state_and_data,
          {:state_timeout, 0, :start_at_created}
        }

      {same, same} ->
        :keep_state_and_data

      {:created, :started} ->
        {:ok, data} = update_workitem(data, :started)
        {:keep_state, data}

      {:started, :completed} ->
        {:keep_state, data}

      {_from, :abandoned} ->
        {:ok, data} = update_workitem(data, :abandoned)
        {:keep_state, data}
    end
  end

  @impl GenStateMachine
  def handle_event(:state_timeout, :start_at_created, :created, %__MODULE__{}) do
    {:keep_state_and_data, [{:next_event, :cast, :start}]}
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
    end
  end

  @impl GenStateMachine
  def handle_event(:cast, :abandon, state, %__MODULE__{} = data)
      when state not in [:abandoned, :completed] do
    {
      :next_state,
      :abandoned,
      data,
      {:next_event, :cast, :stop}
    }
  end

  @impl GenStateMachine
  def handle_event(:cast, :abandon, _state, %__MODULE__{}) do
    :keep_state_and_data
  end

  @impl GenStateMachine
  def handle_event(:cast, :stop, _state, %__MODULE__{} = data) do
    {:stop, :normal, data}
  end

  @impl GenStateMachine
  def handle_event(:cast, _event_content, _state, %__MODULE__{}) do
    :keep_state_and_data
  end

  @impl GenStateMachine
  def handle_event({:call, from}, {:complete, output}, :started, %__MODULE__{} = data) do
    {:ok, data} = do_complete(data, output)

    {
      :next_state,
      :completed,
      data,
      [
        {:reply, from, :ok},
        {:next_event, :cast, :stop}
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

  defp update_workitem(%__MODULE__{} = data, state_and_options) do
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
    end
  end

  defp do_complete(%__MODULE__{} = data, output) do
    {
      :ok,
      %{
        workitem_schema: workitem_schema
      } = data
    } = update_workitem(data, {:completed, output})

    :ok =
      WorkflowMetal.Task.Task.complete_workitem(
        task_server(data),
        workitem_schema
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

    WorkflowMetal.Task.Task.via_name(application, {workflow_id, case_id, transition_id, task_id})
  end
end
