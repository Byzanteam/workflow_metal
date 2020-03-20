defmodule WorkflowMetal.Workflow.Schema.WorkitemAssignment do
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

  @type t() :: %__MODULE__{
          id: any(),
          workflow_id: any(),
          case_id: any(),
          transition_id: any(),
          workitem_id: any(),
          assignee_id: any()
        }
end
