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

  alias WorkflowMetal.Storage.Schema

  @enforce_keys [:id, :workflow_id, :place_id, :transition_id, :direction]
  defstruct [
    :id,
    :workflow_id,
    :place_id,
    :transition_id,
    :direction
  ]

  @type id :: term()
  @type direction :: :in | :out

  @type workflow_id :: Schema.Workflow.id()
  @type place_id :: Schema.Place.id()
  @type transition_id :: Schema.Transition.id()
  @type guard :: Schema.Guard.t()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          place_id: place_id,
          transition_id: transition_id,
          direction: direction
        }

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    @enforce_keys [:place_rid, :transition_rid, :direction]
    defstruct [
      :place_rid,
      :transition_rid,
      :direction
    ]

    @type reference_id :: term()

    @type t() :: %__MODULE__{
            place_rid: reference_id,
            transition_rid: reference_id,
            direction: Arc.direction()
          }
  end
end
