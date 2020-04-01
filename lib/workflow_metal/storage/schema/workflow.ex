defmodule WorkflowMetal.Storage.Schema.Workflow do
  @moduledoc """
  Present a workflow.
  """

  alias WorkflowMetal.Storage.Schema

  @enforce_keys [:id, :state]
  defstruct [
    :id,
    :state
  ]

  @type id :: term()
  @type state :: :drafted | :active | :discarded

  @type t() :: %__MODULE__{
          id: id,
          state: state
        }

  defmodule Params do
    @moduledoc false

    @enforce_keys [:state]
    defstruct [
      :state,
      places: [],
      transitions: [],
      arcs: []
    ]

    @type t() :: %__MODULE__{
            state: Workflow.state(),
            places: [Schema.Place.Params.t()],
            transitions: [Schema.Transition.Params.t()],
            arcs: [Schema.Arc.Params.t()]
          }
  end
end
