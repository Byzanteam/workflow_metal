defmodule WorkflowMetal.Storage.Schema.Task do
  @moduledoc false

  alias WorkflowMetal.Storage.Schema

  @enforce_keys [
    :id,
    :workflow_id,
    :transition_id,
    :case_id,
    :state
  ]
  defstruct [
    :id,
    :workflow_id,
    :transition_id,
    :case_id,
    :token_payload,
    state: :started
  ]

  @type id :: term()
  @type state :: :started | :allocated | :executing | :completed | :abandoned

  @type workflow_id :: Schema.Workflow.id()
  @type transition_id :: Schema.Transition.id()
  @type case_id :: Schema.Case.id()
  @type token_payload :: Schema.Token.payload()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          transition_id: transition_id,
          case_id: case_id,
          state: state,
          token_payload: token_payload
        }

  alias __MODULE__

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
