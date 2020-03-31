defmodule WorkflowMetal.Workitem.Workitem do
  @moduledoc """
  A `GenServer` to run a workitem.
  """

  use GenServer

  defstruct [
    :application,
    :workflow_id,
    :case_id,
    :transition_id,
    :transition,
    :workitem_id,
    :workitem,
    :tokens,
    :workitem_state
  ]

  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()

  @type options :: [
          name: term(),
          case_id: case_id,
          transition_id: transition_id,
          workitem_id: workitem_id
        ]

  @doc false
  @spec start_link(workflow_identifier, options) :: GenServer.on_start()
  def start_link(workflow_identifier, options) do
    name = Keyword.fetch!(options, :name)
    case_id = Keyword.fetch!(options, :case_id)
    transition_id = Keyword.fetch!(options, :transition_id)
    workitem_id = Keyword.fetch!(options, :workitem_id)

    GenServer.start_link(
      __MODULE__,
      {workflow_identifier, case_id, transition_id, workitem_id},
      name: name
    )
  end

  @doc false
  @spec name({workflow_id, case_id, transition_id}) :: term()
  def name({workflow_id, case_id, transition_id}) do
    {__MODULE__, {workflow_id, case_id, transition_id}}
  end

  # callbacks

  @impl true
  def init({{application, workflow_id}, case_id, transition_id, workitem_id}) do
    {
      :ok,
      %__MODULE__{
        application: application,
        workflow_id: workflow_id,
        case_id: case_id,
        transition_id: transition_id,
        workitem_id: workitem_id
      },
      {:continue, :fetch_resources}
    }
  end

  @impl true
  def handle_continue(:fetch_resources, %__MODULE__{} = state) do
    %{
      transition_id: transition_id,
      workitem_id: workitem_id
    } = state

    workflow_server = workflow_server(state)

    {:ok, transition} =
      WorkflowMetal.Workflow.Workflow.fetch_transition(workflow_server, transition_id)

    task_server = task_server(state)
    {:ok, workitem} = WorkflowMetal.Task.Task.fetch_workitem(task_server, workitem_id)

    {
      :noreply,
      %{state | transition: transition, workitem: workitem, workitem_state: workitem.state},
      {:continue, :start_workitem}
    }
  end

  @impl true
  def handle_continue(:start_workitem, %__MODULE__{workitem_state: :created} = state) do
    start_workitem(state)
  end

  def handle_continue(:start_workitem, %__MODULE__{} = state), do: {:noreply, state}

  @doc """
  Update its workitem_state in the storage.
  """
  @impl true
  def handle_continue(:update_workitem_state, %__MODULE__{} = _state) do
    # TODO: update in the Storage
    # %{workitem_state: workitem_state} = state
  end

  @impl true
  def handle_continue({:fail_workitem, error}, %__MODULE__{} = _state) do
    # TODO: update in the Storage
    # %{workitem_state: workitem_state} = state
    #
    # TODO: fail
  end

  @impl true
  def handle_continue({:complete_workitem, token_params}, %__MODULE__{} = state) do
    # TODO: update workitem_state and tokens in the Storage
    # %{workitem_state: workitem_state} = state

    # TODO: issue tokens
  end

  defp start_workitem(%__MODULE__{} = state) do
    %{
      workitem: workitem,
      tokens: tokens,
      transition: %{
        executer: executer,
        executer_params: executer_params
      }
    } = state

    case executer.execute(workitem, tokens, executer_params: executer_params) do
      :started ->
        {:noreply, %{state | workitem_state: :started}, {:continue, :update_workitem_state}}

      {:completed, token_params} ->
        {:noreply, state, {:continue, :complete_workitem, token_params}}

      {:failed, error} ->
        # TODO: logger
        {:noreply, %{state | workitem_state: :failed}, {:continue, {:fail_workitem, error}}}
    end
  end

  defp workflow_server(%__MODULE__{} = state) do
    %{application: application, workflow_id: workflow_id} = state

    WorkflowMetal.Workflow.Workflow.via_name(application, workflow_id)
  end

  defp task_server(%__MODULE__{} = state) do
    %{
      application: application,
      workflow_id: workflow_id,
      case_id: case_id,
      transition_id: transition_id
    } = state

    WorkflowMetal.Task.Task.via_name(application, {workflow_id, case_id, transition_id})
  end
end