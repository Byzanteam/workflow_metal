defmodule WorkflowMetal.Workflow.Supervisor do
  @moduledoc """
  The supervisor of a workflow.
  """

  use Supervisor

  @type application :: WorkflowMetal.Application.t()

  @type workflow :: WorkflowMetal.Storage.Schema.Workflow.t()
  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()

  @type options :: [name: term, workflow: workflow]

  @doc false
  @spec start_link(application, options) :: Supervisor.on_start()
  def start_link(application, options) do
    name = Keyword.fetch!(options, :name)
    workflow_id = Keyword.fetch!(options, :workflow_id)

    Supervisor.start_link(__MODULE__, {application, workflow_id}, name: name)
  end

  @doc false
  @spec name(workflow_id) :: term()
  def name(workflow_id) do
    {__MODULE__, workflow_id}
  end

  ## Callbacks

  @impl true
  def init({application, workflow_id}) do
    children = [
      {WorkflowMetal.Workflow.Workflow, {application, workflow_id}},
      {WorkflowMetal.Case.Supervisor, {application, workflow_id}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
