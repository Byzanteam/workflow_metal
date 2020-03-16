defmodule WorkflowMetal.Workflow.Workflow do
  @moduledoc """
  Workflow is a `GenServer` process used to provide access to a workflow.
  """

  use GenServer

  @type workflow_arg :: WorkflowMetal.Workflow.Supervisor.workflow_arg()

  @doc false
  @spec start_link(workflow_arg) :: GenServer.on_start()
  def start_link({application, workflow_params}) do
    GenServer.start_link(__MODULE__, [], name: via_name(application, workflow_params))
  end

  defp via_name(application, workflow_params) do
    workflow_id = Keyword.fetch!(workflow_params, :workflow_id)

    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end
end
