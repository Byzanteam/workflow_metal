defmodule WorkflowMetal.Storage.Schema.Workflow do
  @moduledoc """
  Present a workflow.
  """

  @enforce_keys [:id]
  defstruct [
    :id,
    places: [],
    transitions: [],
    arcs: []
  ]

  alias WorkflowMetal.Storage.Schema.{
    Arc,
    Place,
    Transition
  }

  @type id :: term()

  @type t() :: %__MODULE__{
          id: id,
          places: [Place.t()],
          transitions: [Transition.t()],
          arcs: [Arc.t()]
        }
end
