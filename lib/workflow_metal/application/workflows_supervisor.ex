defmodule WorkflowMetal.Application.WorkflowsSupervisor do
  @moduledoc """
  Supervise all workflows.
  """

  use DynamicSupervisor

  @doc """
  Start the workflows supervisor to supervise all workflows.
  """
  @spec start_link({module(), atom(), keyword()}) :: Supervisor.on_start()
  def start_link({_application, name, _opts} = args) do
    supervisor_name = supervisor_name(name)

    DynamicSupervisor.start_link(
      __MODULE__,
      args,
      name: supervisor_name
    )
  end

  @impl true
  def init(args) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [args])
  end

  @doc """
  Start a workflow supervisor.
  """
  @spec create_workflow(module(), %{workflow_id: term()}) :: DynamicSupervisor.on_start_child()
  def create_workflow(application, workflow_params) do
    workflow_id = Map.fetch!(workflow_params, :workflow_id)
    workflows_supervisor = supervisor_name(application.supervisor_name())

    child_spec = {
      WorkflowMetal.Workflow.Supervisor,
      [workflow_id: workflow_id]
    }
    DynamicSupervisor.start_child(workflows_supervisor, child_spec)
  end

  defp supervisor_name(name) do
    Module.concat(name, __MODULE__)
  end
end
