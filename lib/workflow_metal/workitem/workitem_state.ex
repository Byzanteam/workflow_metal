defmodule WorkflowMetal.Workitem.WorkitemState do
  @moduledoc """
  A `GenStateMachine` to run a workitem.
  """

  require Logger

  use GenStateMachine,
    callback_mode: [:handle_event_function, :state_enter],
    restart: :temporary

  defstruct [
    :application,
    :workitem_schema,
    tokens: []
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

  # callbacks

  @impl GenStateMachine
  def init({{application, _workflow_id}, workitem_schema}) do
    %{
      state: state
    } = workitem_schema

    {
      :ok,
      state,
      %__MODULE__{
        application: application,
        workitem_schema: workitem_schema
      }
    }
  end

  @impl GenStateMachine
  def handle_event(:enter, old_state, state, %__MODULE__{} = data) do
    case {old_state, state} do
      {:created, :created} ->
        {
          :keep_state_and_data,
          [{:state_timeout, 0, :start_at_created}]
        }

      {same, same} ->
        :keep_state_and_data

      {:created, :started} ->
        {:ok, data} = update_workitem_state(data, :started)
        {:keep_state, data}

      {:started, :completed} ->
        {:ok, data} = update_workitem_state(data, :completed)
        {:keep_state, data}

      {_from, :abandoned} ->
        {:ok, data} = update_workitem_state(data, :abandoned)
        {:keep_state, data}
    end
  end

  @impl GenStateMachine
  def handle_event(:state_timeout, :start_at_created, :created, %__MODULE__{}) do
    {:keep_state_and_data, [{:next_event, :cast, :start}]}
  end

  @impl GenStateMachine
  def handle_event(:cast, :start, :created, %__MODULE__{} = data) do
    {:next_state, :started, data}
  end

  @impl GenStateMachine
  def handle_event(:cast, :abandon, state, %__MODULE__{} = data)
      when state not in [:abandoned, :completed] do
    {:next_state, :abandoned, data}
  end

  def handle_event(:cast, _event_content, _state, %__MODULE__{}) do
    :keep_state_and_data
  end

  @impl GenStateMachine
  def handle_event({:call, from}, {:complete, output}, :started, %__MODULE__{} = data) do
    {:next_state, :completed, data, {:reply, from, [output]}}
  end

  @impl GenStateMachine
  def handle_event({:call, from}, _event_content, _state, %__MODULE__{}) do
    {:keep_state_and_data, {:reply, from, {:error, :invalid_event_content}}}
  end

  @impl GenStateMachine
  def format_status(_reason, [_pdict, state, data]) do
    {:state, %{current_state: state, data: data}}
  end

  defp update_workitem_state(%__MODULE__{} = data, state, _options \\ []) do
    %{
      workitem_schema: workitem_schema
    } = data

    IO.inspect("the state becomes to #{state} from #{workitem_schema.state}.")

    workitem_schema = %{workitem_schema | state: state}

    {:ok, %{data | workitem_schema: workitem_schema}}
  end
end
