defmodule WorkflowMetal.Workflow.Workflow do
  @moduledoc """
  Workflow is a `GenServer` process used to provide access to a workflow.
  """

  use GenServer

  defstruct [
    :table,
    versions: []
  ]

  @type application :: WorkflowMetal.Application.t()
  @type workflow :: WorkflowMetal.Workflow.Supervisor.workflow()
  @type workflow_arg :: WorkflowMetal.Workflow.Supervisor.workflow_arg()
  @type workflow_address :: nil | {pid, String.t()}
  @type workflow_reference :: WorkflowMetal.Workflow.Supervisor.workflow_reference()

  @doc false
  @spec start_link(workflow_arg) :: GenServer.on_start()
  def start_link({application, workflow}) do
    GenServer.start_link(__MODULE__, [workflow: workflow], name: via_name(application, workflow))
  end

  @doc false
  @spec via_name(application, workflow) :: term()
  def via_name(application, workflow) when is_map(workflow) do
    workflow_id = Map.fetch!(workflow, :id)
    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end

  @doc false
  @spec via_name(application, workflow_reference) :: term()
  def via_name(application, workflow_reference) when is_list(workflow_reference) do
    workflow_id = Keyword.fetch!(workflow_reference, :id)
    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end

  @impl true
  def init(workflow: workflow) do
    workflow_version = Map.fetch!(workflow, :version)

    table = :ets.new(:storage, [:set, :private])
    :ets.insert(table, {workflow_version, workflow})

    {:ok, %__MODULE__{table: table, versions: [workflow_version]}}
  end

  @doc false
  @spec whereis_version(application, workflow_reference) :: workflow_address
  def whereis_version(application, workflow_reference) do
    workflow_version = Keyword.fetch!(workflow_reference, :workflow_version)
    workflow_name = via_name(application, workflow_reference)
    GenServer.call(workflow_name, {:whereis_version, workflow_version})
  end

  @impl true
  def handle_call({:whereis_version, workflow_version}, _, state) do
    %{versions: versions} = state

    if Enum.member?(versions, workflow_version) do
      {:reply, {self(), workflow_version}, state}
    else
      {:reply, nil, state}
    end
  end
end
