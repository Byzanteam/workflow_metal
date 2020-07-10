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
    field :state, state(), default: :free
    field :payload, payload(), enforce: false

    field :workflow_id, workflow_id()
    field :case_id, case_id()
    field :place_id, place_id()

    field :produced_by_task_id, task_id()
    field :locked_by_task_id, task_id(), enforce: false
    field :consumed_by_task_id, task_id(), enforce: false
  end

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    use TypedStruct

    typedstruct enforce: true do
      field :payload, Token.payload()

      field :workflow_id, Token.workflow_id()
      field :case_id, Token.case_id()
      field :place_id, Token.place_id()

      # `:genesis` stands for genesis token
      field :produced_by_task_id, Token.task_id() | :genesis
    end
  end
end
