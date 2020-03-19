defmodule WorkflowMetal.Workflow.Workflow do
  @moduledoc """
  Workflow is a `GenServer` process used to provide access to a workflow.
  """

  use GenServer

  @type workflow_arg :: WorkflowMetal.Workflow.Supervisor.workflow_arg()

  @doc false
  @spec start_link(workflow_arg) :: GenServer.on_start()
  def start_link({application, workflow}) do
    GenServer.start_link(__MODULE__, [workflow: workflow], name: via_name(application, workflow))
  end

  defp via_name(application, workflow) do
    workflow_id = Map.fetch!(workflow, :id)

    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end

  @impl true
  def init(workflow: workflow) do
    workflow_version = Map.fetch!(workflow, :version)

    table = :ets.new(:storage, [:set, :private])
    :ets.insert(table, {workflow_version, workflow})

    {:ok, table}
  end
end
