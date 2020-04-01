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

  @type workflow_id :: Schema.Workflow.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          type: type
        }

  defmodule Params do
    @moduledoc false

    @enforce_keys [:rid, :type]
    defstruct [
      :rid,
      :type
    ]

    @type reference_id :: term()

    @type t() :: %__MODULE__{
            rid: reference_id(),
            type: Place.type()
          }
  end
end
