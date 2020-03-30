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
    :tokens
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

    {:noreply, %{state | transition: transition, workitem: workitem}}
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
