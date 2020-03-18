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

  @type workflow_params :: WorkflowMetal.Workflow.Supervisor.workflow_params()

  @spec new(workflow_params) :: __MODULE__.t()
  def new(%{} = params) do
    {:ok, %__MODULE__{id: params[:id], name: params[:name], version: params[:version]}}
  end
end
