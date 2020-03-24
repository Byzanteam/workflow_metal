defmodule WorkflowMetal.Workflow.Workflow do
  @moduledoc """
  Workflow is a `GenServer` process used to provide access to a workflow.
  """

  use GenServer

  defstruct [
    :table
  ]

  @type application :: WorkflowMetal.Application.t()
  @type workflow :: WorkflowMetal.Workflow.Schema.Workflow.t()

  @type workflow_id :: term()
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

  @impl true
  def init(_init_args) do
    table = :ets.new(:storage, [:set, :private])

    {:ok, %__MODULE__{table: table}}
  end
end
