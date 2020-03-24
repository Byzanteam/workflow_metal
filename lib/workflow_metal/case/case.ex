defmodule WorkflowMetal.Case.Case do
  @moduledoc """
  `GenServer` process to present a workflow case.
  """

  use GenServer

  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type case_params :: WorkflowMetal.Case.Supervisor.case_params()

  @doc false
  @spec name(workflow_identifier, case_params) :: term
  def name({application, workflow_id}, case_params) do
    case_id = Keyword.fetch!(case_params, :case_id)
    {__MODULE__, {application, workflow_id, case_id}}
  end

  @impl true
  def init(init_args) do
    {:ok, init_args}
  end
end
