defmodule WorkflowMetal.Storage.Schema.Workitem do
  @moduledoc false

  use TypedStruct

  @type id :: term()
  @type state :: :created | :started | :completed | :abandoned
  @type output :: map() | nil

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()

  typedstruct enforce: true do
    field :id, id()
    field :state, state(), default: :created
    field :output, output(), enforce: false

    field :workflow_id, workflow_id()
    field :transition_id, transition_id()
    field :case_id, case_id()
    field :task_id, task_id()
  end

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    use TypedStruct

    typedstruct enforce: true do
      field :workflow_id, Workitem.workflow_id()
      field :transition_id, Workitem.transition_id()
      field :case_id, Workitem.case_id()
      field :task_id, Workitem.task_id()
    end
  end
end
