defmodule WorkflowMetal.Workitem.Workitem do
  @moduledoc """
  A `GenServer` to run a workitem.
  """

  require Logger

  use GenServer, restart: :temporary

  defstruct [
    :application,
    :workflow_id,
    :case_id,
    :transition_id,
    :transition,
    :workitem_id,
    :workitem,
    :tokens,
    :workitem_state
  ]

  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()

  @type error :: term()
  @type options :: [
          name: term(),
          case_id: case_id,
          transition_id: transition_id,
          workitem_id: workitem_id
        ]

  @doc false
  @spec start_link(workflow_identifier, options) :: GenServer.on_start()
  def start_link(workflow_identifier, options) do
    name = Keyword.fetch!(options, :name)
    case_id = Keyword.fetch!(options, :case_id)
    transition_id = Keyword.fetch!(options, :transition_id)
    workitem_id = Keyword.fetch!(options, :workitem_id)

    GenServer.start_link(
      __MODULE__,
      {workflow_identifier, case_id, transition_id, workitem_id},
      name: name
    )
  end

  @doc false
  @spec name({workflow_id, case_id, transition_id}) :: term()
  def name({workflow_id, case_id, transition_id}) do
    {__MODULE__, {workflow_id, case_id, transition_id}}
  end

  @doc """
  Complete a workitem.
  """
  @spec complete(GenServer.server(), token_params) :: :ok
  def complete(workitem_server, token_params) do
    GenServer.call(workitem_server, {:complet, token_params})
  end

  @doc """
  Fail a workitem.
  """
  @spec fail(GenServer.server(), error) :: :ok
  def fail(workitem_server, error) do
    GenServer.call(workitem_server, {:fail, error})
  end

  # callbacks

  @impl true
  def init({{application, workflow_id}, case_id, transition_id, workitem_id}) do
    {
      :ok,
      %__MODULE__{
        application: application,
        workflow_id: workflow_id,
        case_id: case_id,
        transition_id: transition_id,
        workitem_id: workitem_id
      },
      {:continue, :fetch_resources}
    }
  end

  @impl true
  def handle_continue(:fetch_resources, %__MODULE__{} = state) do
    %{
      transition_id: transition_id,
      workitem_id: workitem_id
    } = state

    workflow_server = workflow_server(state)

    {:ok, transition} =
      WorkflowMetal.Workflow.Workflow.fetch_transition(workflow_server, transition_id)

    task_server = task_server(state)
    {:ok, workitem} = WorkflowMetal.Task.Task.fetch_workitem(task_server, workitem_id)

    {
      :noreply,
      %{state | transition: transition, workitem: workitem, workitem_state: workitem.state},
      {:continue, :start_workitem}
    }
  end

  @impl true
  def handle_continue(:start_workitem, %__MODULE__{workitem_state: :created} = state) do
    start_workitem(state)
  end

  def handle_continue(:start_workitem, %__MODULE__{} = state), do: {:noreply, state}

  @doc """
  Update its workitem_state in the storage.
  """
  @impl true
  def handle_continue(:update_workitem_state, %__MODULE__{} = state) do
    {:ok, workitem} = persist_workitem_state(state)

    {:noreply, %{state | workitem: workitem}}
  end

  @impl true
  def handle_continue({:fail_workitem, error}, %__MODULE__{} = state) do
    Logger.error(fn ->
      """
      The workitem fail to execute, due to: #{inspect(error)}.
      """
    end)

    {:ok, workitem} = persist_workitem_state(state)

    task_server(state).fail_workitem(workitem.id, error)

    {:stop, :normal, %{state | workitem: workitem}}
  end

  @impl true
  def handle_continue({:complete_workitem, token_params}, %__MODULE__{} = state) do
    {:ok, workitem} = persist_workitem_state(state)

    task_server(state).complete_workitem(workitem.id, token_params)

    {:stop, :normal, %{state | workitem: workitem}}
  end

  @impl true
  def handle_call({:complete, token_params}, _from, %__MODULE__{workitem_state: :started} = state) do
    {
      :reply,
      :ok,
      %{state | workitem_state: :completed},
      {:continue, :complete_workitem, token_params}
    }
  end

  def handle_call({:complete, _token_params}, _from, %__MODULE__{} = state) do
    {:reply, {:error, :invalid_state}, state}
  end

  def handle_call({:fail, error}, _from, %__MODULE__{workitem_state: :started} = state) do
    {
      :reply,
      :ok,
      %{state | workitem_state: :failed},
      {:continue, {:fail_workitem, error}}
    }
  end

  def handle_call({:fail, _error}, _from, %__MODULE__{} = state) do
    {:reply, {:error, :invalid_state}, state}
  end

  defp start_workitem(%__MODULE__{} = state) do
    %{
      workitem: workitem,
      tokens: tokens,
      transition: %{
        executer: executer,
        executer_params: executer_params
      }
    } = state

    case executer.execute(workitem, tokens, executer_params: executer_params) do
      :started ->
        {:noreply, %{state | workitem_state: :started}, {:continue, :update_workitem_state}}

      {:completed, token_params} ->
        {:noreply, %{state | workitem_state: :completed},
         {:continue, :complete_workitem, token_params}}

      {:failed, error} ->
        {:noreply, %{state | workitem_state: :failed}, {:continue, {:fail_workitem, error}}}
    end
  end

  defp persist_workitem_state(%__MODULE__{} = state) do
    %{
      workitem: workitem,
      workitem_state: workitem_state
    } = state

    storage(state).update_workitem(%{workitem | state: workitem_state})
  end

  defp workflow_server(%__MODULE__{} = state) do
    %{application: application, workflow_id: workflow_id} = state

    WorkflowMetal.Workflow.Workflow.via_name(application, workflow_id)
  end

  defp task_server(%__MODULE__{} = state) do
    %{
      application: application,
      workflow_id: workflow_id,
      case_id: case_id,
      transition_id: transition_id
    } = state

    WorkflowMetal.Task.Task.via_name(application, {workflow_id, case_id, transition_id})
  end

  defp storage(%__MODULE__{} = state) do
    %{application: application} = state
    WorkflowMetal.Application.storage_adapter(application)
  end
end
