defmodule WorkflowMetal.Workflow.Schemas.Case do
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

  @type t() :: %__MODULE__{
          id: any(),
          workflow_id: any(),
          state: :created | :active | :canceled | :finished,
          activated_at: NaiveDateTime.t(),
          canceled_at: NaiveDateTime.t(),
          finished_at: NaiveDateTime.t()
        }
end
