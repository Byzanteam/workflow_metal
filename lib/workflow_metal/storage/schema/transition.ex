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

  @type id :: term()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          executer: module(),
          executer_params: map()
        }
end
