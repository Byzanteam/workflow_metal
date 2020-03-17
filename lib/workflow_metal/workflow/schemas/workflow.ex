defmodule WorkflowMetal.Workflow.Schemas.Workflow do
  @moduledoc false

  @enforce_keys [:id, :name, :version]
  defstruct [
    :id,
    :name,
    :description,
    :version,
    places: [],
    transitions: [],
    arcs: []
  ]

  alias WorkflowMetal.Workflow.Schemas.{
    Place,
    Transition,
    Arc
  }

  @type t() :: %__MODULE__{
    id: any(),
    name: String.t(),
    description: String.t(),
    version: String.t(),
    places: [Place.t()],
    transitions: [Transition.t()],
    arcs: [Arc.t()]
  }
end
