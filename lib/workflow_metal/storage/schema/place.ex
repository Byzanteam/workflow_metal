defmodule WorkflowMetal.Storage.Schema.Place do
  @moduledoc """
  Present a place.

  There is one `:start`, one `:end`, and several `:normal` places in a workflow.

  ## Type

  - `:normal`
  - `:start`
  - `:end`
  """

  @enforce_keys [:id, :workflow_id, :type]
  defstruct [
    :id,
    :workflow_id,
    :type
  ]

  @type t() :: %__MODULE__{
          id: any(),
          workflow_id: any(),
          type: :start | :normal | :end
        }
end
