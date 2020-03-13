defmodule WorkflowMetal.Workflow.Supervisor do
  @moduledoc """
  The supervisor of a workflow.
  """

  use Supervisor

  @doc false
  def start_link(config, args) do
    Supervisor.start_link(__MODULE__, {config, args}, name: name(config, args))
  end

  defp name({application, name, _opts}, opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    registration = Module.concat(name, Registry)

    {:via, Registry, {registration, {application, __MODULE__, workflow_id}}}
  end

  ## Callbacks

  @impl true
  def init({config, args}) do
    children = [
      {WorkflowMetal.Workflow.Workflow, {config, args}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
