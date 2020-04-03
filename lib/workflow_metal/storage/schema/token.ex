defmodule WorkflowMetal.Storage.Schema.Token do
  @moduledoc false

  alias WorkflowMetal.Storage.Schema

  @enforce_keys [
    :id,
    :state,
    :workflow_id,
    :case_id,
    :place_id,
    :produced_by_task_id
  ]

  defstruct [
    :id,
    :workflow_id,
    :case_id,
    :place_id,
    :produced_by_task_id,
    :locked_by_task_id,
    state: :free
  ]

  @type id :: term()
  @type state :: :created | :free | :locked | :consumed

  @type workflow_id :: Schema.Workflow.id()
  @type place_id :: Schema.Place.id()
  @type case_id :: Schema.Case.id()
  @type task_id :: Schema.Task.id()

  @type t() :: %__MODULE__{
          id: id,
          state: state,
          workflow_id: workflow_id,
          case_id: case_id,
          place_id: place_id,
          produced_by_task_id: task_id,
          locked_by_task_id: task_id
        }

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    @enforce_keys [:workflow_id, :case_id, :place_id, :produced_by_task_id]
    defstruct [
      :workflow_id,
      :case_id,
      :place_id,
      :produced_by_task_id
    ]

    @type t() :: %{
            workflow_id: Token.workflow_id(),
            case_id: Token.case_id(),
            place_id: Token.place_id(),
            # `:genesis` stands for genesis token
            produced_by_task_id: Token.task_id() | :genesis
          }
  end
end
