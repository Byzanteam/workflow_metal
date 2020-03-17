defmodule WorkflowMetal.Workflow.Supervisor do
  @moduledoc """
  The supervisor of a workflow.
  """

  use Supervisor

  @type application :: WorkflowMetal.Application.t()

  @type workflow_params :: %{workflow_id: term(), workflow_version: String.t()}
  @type workflow_arg :: {application, workflow_params}

  @doc false
  @spec start_link(application, workflow_params) :: Supervisor.on_start()
  def start_link(application, workflow_params) do
    Supervisor.start_link(__MODULE__, {application, workflow_params},
      name: via_name(application, workflow_params)
    )
  end

  defp via_name(application, workflow_params) do
    workflow_id = Keyword.fetch!(workflow_params, :workflow_id)

    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end

  ## Callbacks

  @impl true
  def init(workflow_arg) do
    children = [
      {WorkflowMetal.Workflow.Workflow, workflow_arg},
      {WorkflowMetal.VersionManager.Supervisor, workflow_arg}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
