defmodule WorkflowMetal.Workflow.Supervisor do
  @moduledoc """
  The supervisor of a workflow.
  """

  use Supervisor

  @type application :: WorkflowMetal.Application.t()

  @type workflow :: WorkflowMetal.Workflow.Schemas.Workflow.t()
  @type workflow_params :: [workflow_id: term()]
  @type workflow_arg :: {application, workflow}

  @doc false
  @spec start_link(application, workflow) :: Supervisor.on_start()
  def start_link(application, workflow) do
    Supervisor.start_link(__MODULE__, {application, workflow},
      name: via_name(application, workflow)
    )
  end

  defp via_name(application, workflow) do
    workflow_id = Map.fetch!(workflow, :id)

    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end

  ## Callbacks

  @impl true
  def init(workflow_arg) do
    children = [
      {WorkflowMetal.Workflow.Workflow, workflow_arg}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
