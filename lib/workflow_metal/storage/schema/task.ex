defmodule WorkflowMetal.Storage.Schema.Task do
  @moduledoc false

  alias WorkflowMetal.Storage.Schema

  @enforce_keys [
    :id,
    :state,
    :workflow_id,
    :transition_id,
    :case_id
  ]
  defstruct [
    :id,
    :state,
    :workflow_id,
    :transition_id,
    :case_id
  ]

  @type id :: term()
  @type state :: :created | :started | :completed

  @type workflow_id :: Schema.Workflow.id()
  @type transition_id :: Schema.Transition.id()
  @type case_id :: Schema.Case.id()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          case_id: case_id,
          transition_id: transition_id,
          state: state
        }

  defmodule Params do
    @moduledoc false

    @enforce_keys [
      :workflow_id,
      :transition_id,
      :case_id
    ]
    defstruct [
      :workflow_id,
      :transition_id,
      :case_id
    ]

    @type t() :: %__MODULE__{
            workflow_id: Task.workflow_id(),
            transition_id: Task.transition_id(),
            case_id: Task.case_id()
          }
  end
end
