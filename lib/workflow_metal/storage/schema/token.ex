defmodule WorkflowMetal.Storage.Schema.Token do
  @moduledoc false

  @enforce_keys [:state, :workflow_id, :case_id]
  defstruct [
    :state,
    :workflow_id,
    :case_id,
    :place_id,
    :locked_workitem_id
  ]

  @type state :: :free | :locked | :consumed
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()

  @type t() :: %__MODULE__{
          state: state,
          workflow_id: workflow_id,
          place_id: place_id,
          case_id: case_id,
          locked_workitem_id: workitem_id
        }
end
