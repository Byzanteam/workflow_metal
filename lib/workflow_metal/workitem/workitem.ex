defmodule WorkflowMetal.Workitem.Workitem do
  @moduledoc """
  A `GenServer` to run a workitem.
  """

  alias WorkflowMetal.Storage.Schema

  require Logger

  use GenServer, restart: :temporary

  defstruct [
    :application,
    :tokens,
    :workitem_schema
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
    workitem = Keyword.fetch!(options, :workitem)

    GenServer.start_link(
      __MODULE__,
      {workflow_identifier, workitem},
      name: name
    )
  end

  @doc false
  @spec name({workflow_id, case_id, transition_id, workitem_id}) :: term()
  def name({workflow_id, case_id, transition_id, workitem_id}) do
    {__MODULE__, {workflow_id, case_id, transition_id, workitem_id}}
  end

  @doc """
  Complete a workitem.
  """
  @spec complete(GenServer.server(), token_params) :: :ok
  def complete(workitem_server, token_params) do
    GenServer.call(workitem_server, {:complete, token_params})
  end

  # @doc """
  # Fail a workitem.
  # """
  # @spec fail(GenServer.server(), error) :: :ok
  # def fail(workitem_server, error) do
  #   GenServer.call(workitem_server, {:fail, error})
  # end

  # callbacks

  @impl true
  def init({{application, _workflow_id}, workitem_schema}) do
    {
      :ok,
      %__MODULE__{
        application: application,
        workitem_schema: workitem_schema
      },
      {:continue, :lock_tokens}
    }
  end

  @impl true
  def handle_continue(:lock_tokens, %__MODULE__{} = state) do
    %{
      application: application,
      workitem_schema: %{
        task_id: task_id
      }
    } = state

    {:ok, tokens} = WorkflowMetal.Storage.fetch_locked_tokens(application, task_id)

    {
      :noreply,
      %{state | tokens: tokens},
      {:continue, :execute_workitem}
    }
  end

  @impl true
  def handle_continue(
        :execute_workitem,
        %__MODULE__{workitem_schema: %Schema.Workitem{state: :created}} = state
      ) do
    {:ok, state} = do_execute_workitem(state)
    {:noreply, state}
  end

  def handle_continue(:execute_workitem, %__MODULE__{} = state), do: {:noreply, state}

  # @impl true
  # def handle_continue({:fail_workitem, error}, %__MODULE__{} = state) do
  #   Logger.error(fn ->
  #     """
  #     The workitem fail to execute, due to: #{inspect(error)}.
  #     """
  #   end)

  #   {:ok, workitem_schema} =
  #     WorkflowMetal.Storage.fail_workitem(state.application, workitem_schema)

  #   WorkflowMetal.Task.Task.fail_workitem(task_server(state), workitem_schema, error)

  #   {:stop, :normal, %{state | workitem: workitem}}
  # end

  @impl true
  def handle_call(
        {:complete, token_params},
        _from,
        %__MODULE__{workitem_schema: %Schema.Workitem{state: :started}} = state
      ) do
    {:ok, workitem_schema} = do_complete_workitem(state, token_params)

    {:stop, :normal, %{state | workitem_schema: workitem_schema}}
  end

  def handle_call({:complete, _token_params}, _from, %__MODULE__{} = state),
    do: {:stop, :normal, state}

  # def handle_call({:fail, error}, _from, %__MODULE__{workitem_state: :started} = state) do
  #   {
  #     :reply,
  #     :ok,
  #     %{state | workitem_state: :failed},
  #     {:continue, {:fail_workitem, error}}
  #   }
  # end

  # def handle_call({:fail, _error}, _from, %__MODULE__{} = state) do
  #   {:reply, {:error, :invalid_state}, state}
  # end

  defp do_execute_workitem(%__MODULE__{} = state) do
    %{
      application: application,
      workitem_schema:
        %Schema.Workitem{
          transition_id: transition_id
        } = workitem_schema,
      tokens: tokens
    } = state

    {
      :ok,
      %{
        executer: executer,
        executer_params: executer_params
      }
    } = WorkflowMetal.Storage.fetch_transition(application, transition_id)

    case executer.execute(workitem_schema, tokens, executer_params: executer_params) do
      :started ->
        {:ok, workitem_schema} = do_start_workitem(state)
        {:ok, %{state | workitem_schema: workitem_schema}}

      {:completed, token_params} ->
        {:ok, workitem_schema} = do_complete_workitem(token_params, state)
        {:ok, %{state | workitem_schema: workitem_schema}}

        # {:failed, error} ->
        #   {:noreply, %{state | workitem_state: :failed}, {:continue, {:fail_workitem, error}}}
    end
  end

  defp do_start_workitem(%__MODULE__{} = state) do
    %{
      application: application,
      workitem_schema: workitem_schema
    } = state

    {:ok, workitem_schema} = WorkflowMetal.Storage.start_workitem(application, workitem_schema)

    {:ok, workitem_schema}
  end

  defp do_complete_workitem(token_params, %__MODULE__{} = state) do
    %{
      application: application,
      workitem_schema: workitem_schema
    } = state

    {:ok, workitem_schema} = WorkflowMetal.Storage.complete_workitem(application, workitem_schema)

    WorkflowMetal.Task.Task.complete_workitem(task_server(state), workitem_schema, token_params)

    {:ok, workitem_schema}
  end

  defp task_server(%__MODULE__{} = state) do
    %{
      application: application,
      workitem_schema: %{
        workflow_id: workflow_id,
        case_id: case_id,
        transition_id: transition_id
      }
    } = state

    WorkflowMetal.Task.Task.via_name(application, {workflow_id, case_id, transition_id})
  end
end
