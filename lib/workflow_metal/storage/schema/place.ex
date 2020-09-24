defmodule WorkflowMetal.Storage.Schema.Place do
  @moduledoc """
  Present a place.

  There is one `:start`, one `:end`, and several `:normal` places in a workflow.

  ## Type

  - `:normal`
  - `:start`
  - `:end`
  """

  use TypedStruct

  alias WorkflowMetal.Storage.Schema

  @type id :: term()
  @type type :: :start | :normal | :end
  @type metadata :: map() | nil

  @type workflow_id :: Schema.Workflow.id()

  typedstruct enforce: true do
    field :id, id()
    field :type, type()

    field :metadata, metadata(), enforce: false

    field :workflow_id, workflow_id()
  end
end
