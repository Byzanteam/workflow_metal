defmodule WorkflowMetal.Storage.Schema.Arc do
  @moduledoc """
  Present an arc.

  ## Example
  [A(place)] -1-> [B(transition)] -2-> [C(place)]

  ```elixir
    %__MODULE__{
      id: "id-1"
      workflow_id: "workflow_id"
      place_id: A
      transition_id: B
      direction: :out,
      guards: []
    }
    %__MODULE__{
      id: "id-2"
      workflow_id: "workflow_id"
      place_id: C
      transition_id: B
      direction: :in,
      guards: []
    }
  ```
  """

  @enforce_keys [:id, :workflow_id, :place_id, :transition_id, :direction]
  defstruct [
    :id,
    :workflow_id,
    :place_id,
    :transition_id,
    :direction,
    guards: []
  ]

  alias WorkflowMetal.Storage.Schema.Guard

  @type t() :: %__MODULE__{
          id: any(),
          workflow_id: any(),
          place_id: any(),
          transition_id: any(),
          direction: :in | :out,
          guards: [Guard.t()]
        }
end
