defmodule WorkflowMetal.Storage.Schema.Task do
  @moduledoc false

  @enforce_keys [:id, :state, :workflow_id, :case_id, :transition_id]
  defstruct [
    :id,
    :state,
    :workflow_id,
    :case_id,
    :transition_id
  ]

  @type id :: term()
  @type state :: :created | :started | :completed
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          case_id: case_id,
          transition_id: transition_id,
          state: state
        }
end
