defmodule WorkflowMetal.Workflow.Schemas.Arc do
  @moduledoc false

  @enforce_keys [:id, :workflow_id, :place_id, :transition_id, :direction]
  defstruct [
    :id,
    :workflow_id,
    :place_id,
    :transition_id,
    :direction,
    guards: []
  ]

  alias __MODULE__.Guard

  @type t() :: %__MODULE__{
    id: any(),
    workflow_id: any(),
    place_id: any(),
    transition_id: any(),
    direction: :in | :out,
    guards: [Guard.t()]
  }
end
