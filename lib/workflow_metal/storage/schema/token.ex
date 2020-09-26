defmodule WorkflowMetal.Storage.Schema.Token do
  @moduledoc """
  `:genesis` the first token.
  `:termination` the last token.
  """

  use TypedStruct

  alias WorkflowMetal.Storage.Schema

  @type id :: term()
  @type state :: :free | :locked | :consumed
  @type payload :: map() | nil

  @type workflow_id :: Schema.Workflow.id()
  @type place_id :: Schema.Place.id()
  @type case_id :: Schema.Case.id()
  @type task_id :: Schema.Task.id()

  typedstruct enforce: true do
    field :id, id()
    field :state, state()
    field :payload, payload(), enforce: false

    field :workflow_id, workflow_id()
    field :case_id, case_id()
    field :place_id, place_id()

    field :produced_by_task_id, task_id() | :genesis
    field :locked_by_task_id, task_id(), enforce: false
    field :consumed_by_task_id, task_id(), enforce: false
  end
end
