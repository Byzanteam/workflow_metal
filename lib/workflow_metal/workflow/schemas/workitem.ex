defmodule WorkflowMetal.Workflow.Schemas.Workitem do
  @moduledoc false

  @enforce_keys [:id, :workflow_id, :case_id, :transition_id, :state]
  defstruct [
    :id,
    :workflow_id,
    :case_id,
    :transition_id,
    :state,
    :enabled_at,
    :started_at,
    :canceled_at,
    :finished_at,
    workitem_assignments: []
  ]

  alias WorkflowMetal.Workflow.Schemas.WorkitemAssignment

  @type t() :: %__MODULE__{
    id: any(),
    workflow_id: any(),
    case_id: any(),
    transition_id: any(),
    state: :enabled | :started | :canceled | :finished,
    enabled_at: NaiveDateTime.t(),
    started_at: NaiveDateTime.t(),
    canceled_at: NaiveDateTime.t(),
    finished_at: NaiveDateTime.t(),
    workitem_assignments: [WorkitemAssignment.t()]
  }
end
