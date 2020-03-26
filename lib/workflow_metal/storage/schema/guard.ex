defmodule WorkflowMetal.Storage.Schema.Guard do
  @moduledoc """
  Present a guard on an arc.
  """

  @enforce_keys [:id, :arc_id]
  defstruct [
    :id,
    :arc_id,
    :exp,
    :computer
  ]

  @type id :: term()
  @type arc_id :: WorkflowMetal.Storage.Schema.Arc.id()

  @type t() :: %__MODULE__{
          id: id,
          arc_id: arc_id,
          exp: String.t(),
          computer: module()
        }
end
