defmodule WorkflowMetal.Storage.Schema.Task do
  @moduledoc false

  use TypedStruct

  alias WorkflowMetal.Storage.Schema

  @type id :: term()
  @type state :: :started | :allocated | :executing | :completed | :abandoned

  @type workflow_id :: Schema.Workflow.id()
  @type transition_id :: Schema.Transition.id()
  @type case_id :: Schema.Case.id()
  @type token_payload :: Schema.Token.payload()

  typedstruct enforce: true do
    field :id, id()

    field :state, state(), default: :started
    field :token_payload, token_payload(), enforce: false

    field :workflow_id, workflow_id()
    field :transition_id, transition_id()
    field :case_id, case_id()
  end

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    use TypedStruct

    typedstruct enforce: true do
      field :workflow_id, Task.workflow_id()
      field :transition_id, Task.transition_id()
      field :case_id, Task.case_id()
    end
  end
end
