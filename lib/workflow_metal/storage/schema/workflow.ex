defmodule WorkflowMetal.Storage.Schema.Workflow do
  @moduledoc """
  Present a workflow.
  """

  alias WorkflowMetal.Storage.Schema

  @enforce_keys [:id, :state]
  defstruct [
    :id,
    state: :active
  ]

  @type id :: term()
  @type state :: :active | :discarded

  @type t() :: %__MODULE__{
          id: id,
          state: state
        }

  defmodule Params do
    @moduledoc false

    defstruct places: [],
              transitions: [],
              arcs: []

    @type t() :: %__MODULE__{
            places: [Schema.Place.Params.t()],
            transitions: [Schema.Transition.Params.t()],
            arcs: [Schema.Arc.Params.t()]
          }
  end
end
