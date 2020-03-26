defmodule WorkflowMetal.Storage.Schema.WorkitemAssignment do
  @moduledoc false

  @enforce_keys [:id, :workflow_id, :case_id, :transition_id, :workitem_id, :assignee_id]
  defstruct [
    :id,
    :workflow_id,
    :case_id,
    :transition_id,
    :workitem_id,
    :assignee_id
  ]

  @type id :: term()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()
  @type assignee_id :: term()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          transition_id: transition_id,
          case_id: case_id,
          workitem_id: workitem_id,
          assignee_id: assignee_id
        }
end
