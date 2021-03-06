defmodule WorkflowMetal.Workflow.Supervisor do
  @moduledoc """
  The supervisor of a workflow.
  """

  use Supervisor

  @type application :: WorkflowMetal.Application.t()

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type workflow_identifier :: {application, workflow_id}

  @type options :: [name: term, workflow_id: workflow_id]

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
      {WorkflowMetal.Case.Supervisor, {application, workflow_id}},
      {WorkflowMetal.Task.Supervisor, {application, workflow_id}},
      {WorkflowMetal.Workitem.Supervisor, {application, workflow_id}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
