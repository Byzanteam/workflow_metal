defmodule WorkflowMetal.Storage.Schema.Workitem do
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

  alias WorkflowMetal.Storage.Schema.WorkitemAssignment

  @type id :: term()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          case_id: case_id,
          transition_id: transition_id,
          state: :enabled | :started | :canceled | :finished,
          enabled_at: NaiveDateTime.t(),
          started_at: NaiveDateTime.t(),
          canceled_at: NaiveDateTime.t(),
          finished_at: NaiveDateTime.t(),
          workitem_assignments: [WorkitemAssignment.t()]
        }
end
