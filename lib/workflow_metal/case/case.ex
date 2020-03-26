defmodule WorkflowMetal.Case.Case do
  @moduledoc """
  `GenServer` process to present a workflow case.
  """

  use GenServer

  defstruct [
    :application,
    :workflow_id,
    :case_id,
    :table
  ]

  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()

  @doc false
  @spec start_link(workflow_identifier, case_id) :: GenServer.on_start()
  def start_link({application, workflow_id} = workflow_identifier, case_id) do
    via_name =
      WorkflowMetal.Registration.via_tuple(
        application,
        name({workflow_id, case_id})
      )

    GenServer.start_link(__MODULE__, {workflow_identifier, case_id}, name: via_name)
  end

  @doc false
  @spec name({workflow_id, case_id}) :: term
  def name({workflow_id, case_id}) do
    {__MODULE__, {workflow_id, case_id}}
  end

  @impl true
  def init({{application, workflow_id}, case_id}) do
    {
      :ok,
      %__MODULE__{
        application: application,
        workflow_id: workflow_id,
        case_id: case_id
      },
      {:continue, :rebuild_from_storage}
    }
  end

  @impl true
  def handle_continue(:rebuild_from_storage, %__MODULE__{} = state) do
    %{application: application, workflow_id: workflow_id, case_id: case_id, table: table} = state

    case WorkflowMetal.Storage.fetch_case(application, workflow_id, case_id) do
      {:ok, case_schema} ->
        %{id: id} = case_schema
        # TODO: insert tokens ...
        :ets.insert(table, {id, case_schema})
        {:noreply, state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end
end
