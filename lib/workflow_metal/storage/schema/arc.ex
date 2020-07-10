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
      direction: :out
    }
    %__MODULE__{
      id: "id-2"
      workflow_id: "workflow_id"
      place_id: C
      transition_id: B
      direction: :in
    }
  ```
  """

  use TypedStruct

  alias WorkflowMetal.Storage.Schema

  @type id :: term()
  @type direction :: :in | :out

  @type workflow_id :: Schema.Workflow.id()
  @type place_id :: Schema.Place.id()
  @type transition_id :: Schema.Transition.id()
  @type metadata :: map()

  typedstruct enforce: true do
    field :id, id()

    field :place_id, place_id()
    field :direction, direction()
    field :transition_id, transition_id()

    field :metadata, metadata(), enforce: false

    field :workflow_id, workflow_id()
  end

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    use TypedStruct

    typedstruct do
      field :id, Arc.id()

      field :place_id, Arc.id(), enforce: true
      field :direction, Arc.direction(), enforce: true
      field :transition_id, Arc.id(), enforce: true

      field :metadata, Arc.metadata()
    end
  end
end
