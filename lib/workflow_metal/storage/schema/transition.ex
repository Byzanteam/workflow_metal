defmodule WorkflowMetal.Storage.Schema.Transition do
  @moduledoc """
  Present a transition.
  """

  @enforce_keys [:id, :workflow_id]
  defstruct [
    :id,
    :workflow_id,
    :join_type,
    :split_type,
    :executer,
    executer_params: %{}
  ]

  @type id :: term()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type join_type :: :none | :and
  @type split_type :: :none | :and

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          join_type: join_type,
          split_type: split_type,
          executer: module(),
          executer_params: map()
        }
end
