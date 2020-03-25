defmodule WorkflowMetal.Storage.Schema.Arc.Guard do
  @moduledoc false

  @enforce_keys [:id, :arc_id]
  defstruct [
    :id,
    :arc_id,
    :exp,
    :computer
  ]

  @type t() :: %__MODULE__{
          id: any(),
          arc_id: any(),
          exp: String.t(),
          computer: module()
        }
end
