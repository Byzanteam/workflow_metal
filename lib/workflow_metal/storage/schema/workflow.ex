defmodule WorkflowMetal.Storage.Schema.Workflow do
  @moduledoc false

  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    :description,
    places: [],
    transitions: [],
    arcs: []
  ]

  alias WorkflowMetal.Storage.Schema.{
    Arc,
    Place,
    Transition
  }

  @type t() :: %__MODULE__{
          id: any(),
          name: String.t(),
          description: String.t(),
          places: [Place.t()],
          transitions: [Transition.t()],
          arcs: [Arc.t()]
        }

  @type workflow_params :: WorkflowMetal.Workflow.Supervisor.workflow_params()

  @doc """
  Build a Workflow struct from a map
  """
  @spec new(workflow_params) :: {:ok, __MODULE__.t()}
  def new(params) when is_list(params) do
    {:ok,
     %__MODULE__{
       id: params[:workflow_id],
       name: params[:name],
       description: params[:description],
       arcs: [],
       places: [],
       transitions: []
     }}
  end
end
