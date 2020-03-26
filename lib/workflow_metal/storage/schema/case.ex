defmodule WorkflowMetal.Storage.Schema.Case do
  @moduledoc false

  @enforce_keys [:id, :workflow_id]
  defstruct [
    :id,
    :workflow_id,
    :state,
    :activated_at,
    :canceled_at,
    :finished_at
  ]

  @type id :: term()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          state: :created | :active | :canceled | :finished,
          activated_at: NaiveDateTime.t(),
          canceled_at: NaiveDateTime.t(),
          finished_at: NaiveDateTime.t()
        }
end
