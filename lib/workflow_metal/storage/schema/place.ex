defmodule WorkflowMetal.Storage.Schema.Place do
  @moduledoc """
  Present a place.

  There is one `:start`, one `:end`, and several `:normal` places in a workflow.

  ## Type

  - `:normal`
  - `:start`
  - `:end`
  """

  alias WorkflowMetal.Storage.Schema

  @enforce_keys [:id, :workflow_id, :type]
  defstruct [
    :id,
    :workflow_id,
    :type
  ]

  @type id :: term()
  @type type :: :start | :normal | :end

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          type: type
        }

  defmodule Params do
    @moduledoc false

    @enforce_keys [:workflow_id, :type]
    defstruct [
      :workflow_id,
      :type
    ]

    @type t() :: %__MODULE__{
            workflow_id: workflow_id,
            type: Place.type()
          }
  end
end
