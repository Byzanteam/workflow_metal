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
  @type metadata :: map() | nil

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
end
