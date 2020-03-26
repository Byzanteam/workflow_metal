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

  @type id :: term()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          type: :start | :normal | :end
        }
end
