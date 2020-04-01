defmodule WorkflowMetal.Storage.Schema.Transition do
  @moduledoc """
  Present a transition.
  """

  alias WorkflowMetal.Storage.Schema

  @enforce_keys [:id, :workflow_id, :join_type, :split_type, :executer]
  defstruct [
    :id,
    :workflow_id,
    :join_type,
    :split_type,
    :executer,
    :executer_params
  ]

  @type id :: term()
  @type join_type :: :none | :and
  @type split_type :: :none | :and
  @type executer :: module()
  @type executer_params :: term()

  @type workflow_id :: Schema.Workflow.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          join_type: join_type,
          split_type: split_type,
          executer: module(),
          executer_params: map()
        }

  defmodule Params do
    @moduledoc false

    @enforce_keys [:rid, :executer]
    defstruct [
      :rid,
      :executer,
      :executer_params,
      join_type: :none,
      split_type: :none
    ]

    @type reference_id :: term()

    @type t() :: %__MODULE__{
            rid: reference_id,
            join_type: Transition.join_type(),
            split_type: Transition.split_type(),
            executer: Transition.executer(),
            executer_params: Transition.executer_params()
          }
  end
end
