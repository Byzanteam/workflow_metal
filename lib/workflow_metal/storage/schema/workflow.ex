defmodule WorkflowMetal.Storage.Schema.Workflow do
  @moduledoc """
  Present a workflow.
  """

  use TypedStruct

  alias WorkflowMetal.Storage.Schema

  @type id :: term()
  @type metadata :: map()
  @type state :: :active | :discarded

  typedstruct enforce: true do
    field :id, id()
    field :state, state()
    field :metadata, metadata()
  end

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    use TypedStruct

    typedstruct do
      field :id, Workflow.id()

      field :places, [Schema.Place.Params.t()], default: []
      field :transitions, [Schema.Transition.Params.t()], default: []
      field :arcs, [Schema.Arc.Params.t()], default: []

      field :metadata, Workflow.metadata(), default: %{}
    end
  end
end
