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

  @type id :: term()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()

  alias WorkflowMetal.Storage.Schema.Guard

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          place_id: place_id,
          transition_id: transition_id,
          direction: :in | :out,
          guards: [Guard.t()]
        }
end
