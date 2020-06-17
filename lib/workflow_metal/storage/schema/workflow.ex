defmodule WorkflowMetal.Storage.Schema.Workflow do
  @moduledoc """
  Present a workflow.
  """

  alias WorkflowMetal.Storage.Schema

  @enforce_keys [:id, :state]
  defstruct [
    :id,
    :metadata,
    state: :active
  ]

  @type id :: term()
  @type metadata :: map()
  @type state :: :active | :discarded

  @type t() :: %__MODULE__{
          id: id,
          metadata: metadata,
          state: state
        }

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    defstruct [
      :id,
      :metadata,
      places: [],
      transitions: [],
      arcs: []
    ]

    @type t() :: %__MODULE__{
            id: Workflow.id(),
            places: [Schema.Place.Params.t()],
            transitions: [Schema.Transition.Params.t()],
            arcs: [Schema.Arc.Params.t()],
            metadata: Workflow.metadata()
          }
  end
end
