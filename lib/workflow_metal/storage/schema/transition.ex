defmodule WorkflowMetal.Storage.Schema.Transition do
  @moduledoc """
  Present a transition.
  """

  @enforce_keys [:id, :workflow_id, :executer]
  defstruct [
    :id,
    :workflow_id,
    :executer,
    executer_params: %{}
  ]

  @type t() :: %__MODULE__{
          id: any(),
          workflow_id: any(),
          executer: module(),
          executer_params: map()
        }
end
