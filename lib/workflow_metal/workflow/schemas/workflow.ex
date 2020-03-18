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
    Arc,
    Place,
    Transition
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

  @doc """
  Build a Workflow struct from a map
  """
  @spec new(workflow_params) :: {:ok, __MODULE__.t()}
  def new(%{} = params) do
    {:ok,
     %__MODULE__{
       id: params[:id],
       name: params[:name],
       description: params[:description],
       version: params[:version],
       arcs: [],
       places: [],
       transitions: []
     }}
  end
end
