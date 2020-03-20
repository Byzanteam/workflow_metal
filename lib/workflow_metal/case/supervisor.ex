defmodule WorkflowMetal.Case.Supervisor do
  @moduledoc """
  `DynamicSupervisor` to supervise all case of a workflow.
  """

  use DynamicSupervisor

  @type application :: WorkflowMetal.Application.t()
  @type workflow :: WorkflowMetal.Workflow.Supervisor.workflow()
  @type workflow_arg :: WorkflowMetal.Workflow.Supervisor.workflow_arg()

  @doc false
  @spec start_link(workflow_arg) :: Supervisor.on_start()
  def start_link({application, workflow}) do
    DynamicSupervisor.start_link(__MODULE__, [], name: via_name(application, workflow))
  end

  @doc false
  @spec via_name(application, workflow) :: term
  def via_name(application, workflow) do
    workflow_id = Map.fetch!(workflow, :id)
    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
