defmodule WorkflowMetal.Storage.Schema.Transition do
  @moduledoc """
  Present a transition.
  """

  use TypedStruct

  alias WorkflowMetal.Storage.Schema

  @type id :: term()
  @type join_type :: atom()
  @type split_type :: atom()
  @type executor :: module()
  @type executor_params :: term()
  @type metadata :: map()

  @type workflow_id :: Schema.Workflow.id()

  typedstruct enforce: true do
    field :id, id()

    field :join_type, join_type()
    field :split_type, split_type()
    field :executor, module()
    field :executor_params, map(), enforce: false

    field :metadata, map(), enforce: false

    field :workflow_id, workflow_id()
  end

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    use TypedStruct

    typedstruct do
      field :id, Transition.id(), enforce: true

      field :join_type, Transition.join_type(), default: :none
      field :split_type, Transition.split_type(), default: :none
      field :executor, Transition.executor(), enforce: true
      field :executor_params, Transition.executor_params()

      field :metadata, Transition.metadata()
    end
  end
end
