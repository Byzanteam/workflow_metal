defmodule WorkflowMetal.Workflow.Schemas.Transition do
  @moduledoc false

  @enforce_keys [:id, :workflow_id, :name, :executer]
  defstruct [
    :id,
    :workflow_id,
    :name,
    :description,
    :executer,
    executer_params: %{}
  ]

  @type t() :: %__MODULE__{
    id: any(),
    workflow_id: any(),
    name: String.t(),
    description: String.t(),
    executer: module(),
    executer_params: map()
  }
end
