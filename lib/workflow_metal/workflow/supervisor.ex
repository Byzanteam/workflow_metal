defmodule WorkflowMetal.Workflow.Supervisor do
  @moduledoc """
  The supervisor of a workflow.
  """

  use Supervisor

  @type application :: WorkflowMetal.Application.t()

  @type workflow :: WorkflowMetal.Workflow.Schema.Workflow.t()
  @type workflow_id :: term()
  @type workflow_params :: [workflow_id: workflow_id]
  @type workflow_arg :: {application, workflow}
  @type workflow_reference :: [workflow_id: term()]

  @type options :: [name: term, workflow: workflow]

  @doc false
  @spec start_link(application, options) :: Supervisor.on_start()
  def start_link(application, options) do
    name = Keyword.fetch!(options, :name)
    workflow = Keyword.fetch!(options, :workflow)

    Supervisor.start_link(__MODULE__, {application, workflow}, name: name)
  end

  @doc false
  @spec name(workflow | workflow_reference) :: term()
  def name(workflow) do
    workflow_id = Keyword.fetch!(workflow, :workflow_id)
    {__MODULE__, workflow_id}
  end

  @doc false
  @spec via_name(application, workflow | workflow_reference) :: term()
  def via_name(application, workflow) do
    workflow_id = Keyword.fetch!(workflow, :workflow_id)
    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end

  ## Callbacks

  @impl true
  def init(workflow_arg) do
    children = [
      {WorkflowMetal.Workflow.Workflow, workflow_arg},
      {WorkflowMetal.Case.Supervisor, workflow_arg}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
