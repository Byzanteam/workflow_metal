defmodule WorkflowMetal.Storage.Schema.Transition do
  @moduledoc """
  Present a transition.
  """

  alias WorkflowMetal.Storage.Schema

  @enforce_keys [:id, :workflow_id, :join_type, :split_type, :executor]
  defstruct [
    :id,
    :workflow_id,
    :join_type,
    :split_type,
    :executor,
    :executor_params
  ]

  @type id :: term()
  @type join_type :: :none | :and
  @type split_type :: :none | :and
  @type executor :: module()
  @type executor_params :: term()

  @type workflow_id :: Schema.Workflow.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          join_type: join_type,
          split_type: split_type,
          executor: module(),
          executor_params: map()
        }

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    @enforce_keys [:rid, :executor]
    defstruct [
      :rid,
      :executor,
      :executor_params,
      join_type: :none,
      split_type: :none
    ]

    @type reference_id :: term()

    @type t() :: %__MODULE__{
            rid: reference_id,
            join_type: Transition.join_type(),
            split_type: Transition.split_type(),
            executor: Transition.executor(),
            executor_params: Transition.executor_params()
          }
  end
end
