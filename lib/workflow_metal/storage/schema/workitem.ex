defmodule WorkflowMetal.Storage.Schema.Workitem do
  @moduledoc false

  @enforce_keys [:id, :state, :workflow_id, :case_id, :task_id]
  defstruct [
    :id,
    :state,
    :workflow_id,
    :case_id,
    :task_id,
    :transition_id
  ]

  @type id :: term()
  @type state :: :created | :started | :suspended | :failed | :completed
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          case_id: case_id,
          task_id: task_id,
          transition_id: transition_id,
          state: state
        }

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    @enforce_keys [:state, :workflow_id, :case_id, :task_id]
    defstruct [
      :workflow_id,
      :case_id,
      :task_id,
      :state
    ]

    @type t() :: %__MODULE__{
            workflow_id: Workitem.workflow_id(),
            case_id: Workitem.case_id(),
            task_id: Workitem.task_id(),
            state: Workitem.state()
          }
  end
end
