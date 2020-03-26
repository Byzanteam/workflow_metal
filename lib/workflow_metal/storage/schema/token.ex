defmodule WorkflowMetal.Storage.Schema.Token do
  @moduledoc false

  @enforce_keys [:id, :workflow_id, :case_id, :state, :produced_at]
  defstruct [
    :id,
    :state,
    :workflow_id,
    :place_id,
    :case_id,
    :locked_workitem_id,
    :produced_at,
    :locked_at,
    :canceled_at,
    :consumed_at
  ]

  @type id :: term()
  @type state :: :free | :locked | :canceled | :finished
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()

  @type t() :: %__MODULE__{
          id: id,
          state: state,
          workflow_id: workflow_id,
          place_id: place_id,
          case_id: case_id,
          locked_workitem_id: workitem_id,
          produced_at: NaiveDateTime.t(),
          locked_at: NaiveDateTime.t(),
          canceled_at: NaiveDateTime.t(),
          consumed_at: NaiveDateTime.t()
        }
end
