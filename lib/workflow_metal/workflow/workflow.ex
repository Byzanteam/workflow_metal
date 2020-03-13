defmodule WorkflowMetal.Workflow.Workflow do
  @moduledoc """
  Workflow is a `GenServer` process used to provide access to a workflow.
  """

  use GenServer

  def start_link({config, args}) do
    GenServer.start_link(__MODULE__, [], name: name(config, args))
  end

  defp name({application, name, _opts}, opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    registration = Module.concat(name, Registry)

    {:via, Registry, {registration, {application, __MODULE__, workflow_id}}}
  end

  @impl true
  def init(state) do
    {:ok, state}
  end
end
