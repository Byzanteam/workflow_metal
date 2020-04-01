defmodule WorkflowMetal.Task.Task do
  @moduledoc """
  A `GenServer` to hold tokens, execute conditions and generate `workitem`.
  """

  use GenServer

  defstruct [
    :application,
    :workflow_id,
    :case_id,
    :transition_id,
    :task_state,
    :transition,
    :token_table,
    :workitem_table
  ]

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()

  @type task_schema :: WorkflowMetal.Storage.Schema.Task.t()
  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()
  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()

  @type error :: term()
  @type options :: [
          name: term(),
          task: task_schema(),
        ]

  alias WorkflowMetal.Storage.Schema

  @doc false
  @spec start_link(workflow_identifier, options) :: GenServer.on_start()
  def start_link(workflow_identifier, options) do
    name = Keyword.fetch!(options, :name)
    task = Keyword.fetch!(options, :task)

    GenServer.start_link(
      __MODULE__,
      {workflow_identifier, task},
      name: name
    )
  end

  @doc false
  @spec name({workflow_id, case_id, transition_id}) :: term()
  def name({workflow_id, case_id, transition_id}) do
    {__MODULE__, {workflow_id, case_id, transition_id}}
  end

  @doc false
  @spec via_name(application, {workflow_id, case_id, transition_id}) :: term()
  def via_name(application, {workflow_id, case_id, transition_id}) do
    WorkflowMetal.Registration.via_tuple(
      application,
      name({workflow_id, case_id, transition_id})
    )
  end

  @doc """
  Offer a token.
  """
  @spec offer_token(GenServer.server(), place_id, token_id) :: :ok
  def offer_token(task_server, place_id, token_id) do
    GenServer.cast(task_server, {:offer_token, place_id, token_id})
  end

  @doc """
  Withdraw a token.
  """
  @spec withdraw_token(GenServer.server(), place_id, token_id) :: :ok
  def withdraw_token(task_server, place_id, token_id) do
    GenServer.cast(task_server, {:withdraw_token, place_id, token_id})
  end

  @doc """
  Retrive a workitem of the task.
  """
  @spec fetch_workitem(GenServer.server(), workitem_id) ::
          {:ok, workitem_schema} | {:error, term()}
  def fetch_workitem(transition_server, workitem_id) do
    GenServer.call(transition_server, {:fetch_tokens, workitem_id})
  end

  @doc """
  """
  @spec complete_workitem(GenServer.server(), workitem_id, token_params) :: :ok
  def complete_workitem(task_server, workitem_id, token_params) do
    GenServer.cast(task_server, {:complete_workitem, workitem_id, token_params})
  end

  @doc """
  """
  @spec fail_workitem(GenServer.server(), workitem_id, error) :: :ok
  def fail_workitem(task_server, workitem_id, error) do
    GenServer.cast(task_server, {:fail_workitem, workitem_id, error})
  end

  # callbacks

  @impl true
  def init({{application, workflow_id}, task}) do
    token_table = :ets.new(:token_table, [:set, :private])
    workitem_table = :ets.new(:workitem_table, [:set, :private])

    {
      :ok,
      %__MODULE__{
        application: application,
        workflow_id: task.workflow_id,
        case_id: task.case_id,
        transition_id: task.transition_id,
        task_state: task.state,
        token_table: token_table,
        workitem_table: workitem_table
      },
      {:continue, :fetch_transition}
    }
  end

  @impl true
  def handle_continue(:fetch_transition, %__MODULE__{} = state) do
    %{transition_id: transition_id} = state

    workflow_server = workflow_server(state)

    {:ok, transition} =
      WorkflowMetal.Workflow.Workflow.fetch_transition(workflow_server, transition_id)

    {:noreply, %{state | transition: transition}}
  end

  @impl true
  def handle_continue(:fire_transition, %__MODULE__{} = state) do
    if enabled?(state) do
      # TODO: lock token
      # TODO: generate workitem
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_continue(:complete_task, %__MODULE__{} = state) do
    if completed?(state) do
      # TODO: consume token
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:fetch_workitem, workitem_id}, _from, %__MODULE__{} = state) do
    # TODO: find workitem by workitem_id
    %{
      workflow_id: workflow_id,
      case_id: case_id,
      transition_id: transition_id
    } = state

    workitem = %Schema.Workitem{
      id: workitem_id,
      state: :created,
      workflow_id: workflow_id,
      case_id: case_id,
      transition_id: transition_id,
      # TODO:
      task_id: make_ref()
    }

    {:reply, workitem, state}
  end

  @impl true
  def handle_cast({:offer_token, place_id, token_id}, %__MODULE__{} = state) do
    %{token_table: token_table} = state
    :ets.insert(token_table, {token_id, place_id, :free})

    {:noreply, state, {:continue, :fire_transition}}
  end

  @impl true
  def handle_cast({:withdraw_token, _place_id, _token_id}, %__MODULE__{} = _state) do
    # TODO: remove token from token_table
  end

  @impl true
  def handle_cast({:complete_workitem, _place_id, _token_params}, %__MODULE__{} = state) do
    # TODO:
    # - update workitem state
    # - issue tokens

    {:noreply, state, {:continue, :complete_task}}
  end

  @impl true
  def handle_cast({:fail_workitem, _place_id, _error}, %__MODULE__{} = state) do
    # TODO:
    # - update workitem state
    # - issue tokens

    {:noreply, state}
  end

  defp enabled?(%__MODULE__{} = state) do
    %{
      transition_id: transition_id,
      transition: transition,
      token_table: token_table
    } = state

    workflow_server = workflow_server(state)

    {:ok, places} =
      WorkflowMetal.Workflow.Workflow.fetch_places(workflow_server, transition_id, :in)

    # TODO: fetch in arcs with places
    # TODO: consider conditions on the arc
    # WorkflowMetal.Workflow.Workflow.fetch_arcs(workflow_server, transition_id, :in)
    Enum.all?(places, fn place ->
      # TODO: use select_count
      # :ets.select_count > 0
      case transition.join_type do
        :none ->
          [] !== :ets.select(token_table, [{{:"$1", place.id, :free}, [], [:"$1"]}])

        _ ->
          false
      end
    end)
  end

  defp completed?(%__MODULE__{} = _state) do
    true
  end

  defp workflow_server(%__MODULE__{} = state) do
    %{application: application, workflow_id: workflow_id} = state

    WorkflowMetal.Workflow.Workflow.via_name(application, workflow_id)
  end
end
