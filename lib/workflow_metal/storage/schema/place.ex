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
    :type,
    :metadata
  ]

  @type id :: term()
  @type type :: :start | :normal | :end
  @type metadata :: map()

  @type workflow_id :: Schema.Workflow.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          type: type,
          metadata: metadata
        }

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    @enforce_keys [:rid, :type]
    defstruct [
      :id,
      :rid,
      :type,
      :metadata
    ]

    @type reference_id :: term()

    @type t() :: %__MODULE__{
            id: Place.id(),
            rid: reference_id(),
            type: Place.type(),
            metadata: Place.metadata()
          }
  end
end
