defmodule WorkflowMetal.Workflow.Workflow do
  @moduledoc """
  Workflow is a `GenServer` process used to provide access to a workflow.
  """

  use GenServer, restart: :temporary

  defstruct [
    :application,
    :workflow_id
  ]

  @type application :: WorkflowMetal.Application.t()

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type workflow_identifier :: {application, workflow_id}

  @doc false
  @spec start_link(workflow_identifier) :: GenServer.on_start()
  def start_link({application, workflow_id} = workflow_identifier) do
    via_name =
      WorkflowMetal.Registration.via_tuple(
        application,
        name(workflow_id)
      )

    GenServer.start_link(__MODULE__, workflow_identifier, name: via_name)
  end

  @doc false
  @spec name(workflow_identifier) :: term()
  def name(workflow_id) do
    {__MODULE__, workflow_id}
  end

  @doc false
  @spec via_name(application, workflow_identifier) :: term()
  def via_name(application, workflow_id) do
    WorkflowMetal.Registration.via_tuple(application, name(workflow_id))
  end

  # Server (callbacks)

  @impl true
  def init({application, workflow_id}) do
    {
      :ok,
      %__MODULE__{
        application: application,
        workflow_id: workflow_id
      }
    }
  end
end
