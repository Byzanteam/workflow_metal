defmodule WorkflowMetal.Workflow.Workflow do
  @moduledoc """
  Workflow is a `GenServer` process used to provide access to a workflow.
  """

  use GenServer

  defstruct [
    :application,
    :workflow_id,
    :table
  ]

  @type application :: WorkflowMetal.Application.t()
  @type workflow :: WorkflowMetal.Storage.Schema.Workflow.t()

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

  @impl true
  def init({application, workflow_id}) do
    table = :ets.new(:storage, [:set, :private])

    {
      :ok,
      %__MODULE__{
        application: application,
        workflow_id: workflow_id,
        table: table
      },
      {:continue, :rebuild_from_storage}
    }
  end

  @impl true
  def handle_continue(:rebuild_from_storage, %__MODULE__{} = state) do
    %{application: application, workflow_id: workflow_id, table: table} = state

    case WorkflowMetal.Storage.fetch_workflow(application, workflow_id) do
      {:ok, workflow_schema} ->
        %{id: id} = workflow_schema
        # TODO: insert the net
        :ets.insert(table, {id, workflow_schema})
        {:noreply, state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end
end
