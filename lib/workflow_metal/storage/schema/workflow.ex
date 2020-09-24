defmodule WorkflowMetal.Storage.Schema.Workflow do
  @moduledoc """
  Present a workflow.
  """

  use TypedStruct

  @type id :: term()
  @type metadata :: map()
  @type state :: :active | :discarded

  typedstruct enforce: true do
    field :id, id()
    field :state, state()
    field :metadata, metadata(), enforce: false
  end
end
