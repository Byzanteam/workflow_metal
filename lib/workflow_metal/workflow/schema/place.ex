defmodule WorkflowMetal.Workflow.Schema.Place do
  @moduledoc false

  @enforce_keys [:id, :workflow_id, :name, :type]
  defstruct [
    :id,
    :workflow_id,
    :name,
    :description,
    :type
  ]

  @type t() :: %__MODULE__{
          id: any(),
          workflow_id: any(),
          name: String.t(),
          description: String.t(),
          type: :start | :normal | :end
        }
end
