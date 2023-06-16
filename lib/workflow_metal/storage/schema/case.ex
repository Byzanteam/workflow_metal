defmodule WorkflowMetal.Storage.Schema.Case do
  @moduledoc """
  ## State
  - `:created`: the case is just created, we'll put a token in the `:start` place
  - `:active`: the case is running
  - `:terminated`: the case can be terminated by a user who created it or the system
  - `:finished`: when there is only one token left in the `:end` place
  """

  use TypedStruct

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @type id() :: term()
  @type state() :: :created | :active | :terminated | :finished

  @type workflow_id() :: WorkflowMetal.Storage.Schema.Workflow.id()

  typedstruct enforce: true do
    field :id, id(), enforce: false
    field :state, state()

    field :workflow_id, workflow_id()
  end
end
