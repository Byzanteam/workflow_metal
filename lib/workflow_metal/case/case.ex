defmodule WorkflowMetal.Case.Case do
  @moduledoc """
  `GenServer` process to present a workflow case.
  """

  use GenServer

  defstruct [
    :application,
    :workflow_id,
    :case_id,
    :state,
    :token_table
  ]

  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()

  alias WorkflowMetal.Storage.Schema

  @doc false
  @spec start_link(workflow_identifier, case_id) :: GenServer.on_start()
  def start_link(workflow_identifier, options) do
    name = Keyword.fetch!(options, :name)
    case_id = Keyword.fetch!(options, :case_id)

    GenServer.start_link(__MODULE__, {workflow_identifier, case_id}, name: name)
  end

  @doc false
  @spec name({workflow_id, case_id}) :: term
  def name({workflow_id, case_id}) do
    {__MODULE__, {workflow_id, case_id}}
  end

  @doc """
  Lock a token.
  """
  @spec lock(GenServer.server(), case_id) :: :ok | {:error, :failed}
  def lock(case_server, token_id) do
    # TODO
    GenServer.call(case_server, {:lock, token_id})
  end

  @impl true
  def init({{application, workflow_id}, case_id}) do
    token_table = :ets.new(:storage, [:set, :private])

    case WorkflowMetal.Storage.fetch_case(application, workflow_id, case_id) do
      {:ok, %Schema.Case{} = case_schema} ->
        %{state: state} = case_schema

        {
          :ok,
          %__MODULE__{
            application: application,
            workflow_id: workflow_id,
            case_id: case_id,
            state: state,
            token_table: token_table
          },
          {:continue, :rebuild_from_storage}
        }

      {:error, _reason} = reply ->
        reply
    end
  end

  @impl true
  def handle_continue(:rebuild_from_storage, %__MODULE__{} = state) do
    with({:ok, state} <- rebuild_tokens(state)) do
      {:noreply, state, {:continue, :activate_case}}
    else
      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_continue(:activate_case, %__MODULE__{state: :created} = state) do
    {:ok, state} = activate_case(state)
    {:noreply, state, {:continue, :offer_tokens}}
  end

  def handle_continue(:activate_case, state), do: {:noreply, state}

  @impl true
  def handle_continue(:offer_tokens, %__MODULE__{} = state) do
    {:ok, state} = offer_tokens(state)
    {:noreply, state}
  end

  @impl true
  def handle_continue(:fire_transitions, %__MODULE__{} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_call({:lock, _token_id}, _from, %__MODULE__{} = state) do
    # lock token
    withdraw_tokens(state)
  end

  defp rebuild_tokens(%__MODULE__{} = state) do
    %{
      application: application,
      workflow_id: workflow_id,
      case_id: case_id,
      token_table: token_table
    } = state

    case WorkflowMetal.Storage.fetch_tokens(application, workflow_id, case_id, [:free]) do
      {:ok, tokens} ->
        Enum.each(tokens, &upsert_token(token_table, &1))

        {:ok, state}

      {:error, _reason} = reply ->
        reply
    end
  end

  defp upsert_token(token_table, %Schema.Token{} = token) do
    %{
      id: token_id,
      state: state,
      place_id: place_id,
      locked_workitem_id: locked_workitem_id
    } = token

    :ets.insert(token_table, {token_id, state, place_id, locked_workitem_id})
  end

  defp activate_case(%__MODULE__{} = state) do
    %{
      application: application,
      workflow_id: workflow_id,
      case_id: case_id,
      token_table: token_table
    } = state

    workflow_server = workflow_server(state)

    {:ok, %{id: start_place_id}} =
      WorkflowMetal.Workflow.Workflow.fetch_place(workflow_server, :start)

    start_token_params = %Schema.Token.Params{
      state: :free,
      workflow_id: workflow_id,
      case_id: case_id,
      place_id: start_place_id
    }

    {:ok, token_schema} = WorkflowMetal.Storage.create_token(application, start_token_params)

    upsert_token(token_table, token_schema)

    {:ok, state}
  end

  defp offer_tokens(%__MODULE__{} = state) do
    %{token_table: token_table} = state

    match_spec =
      :ets.fun2ms(fn {token_id, state, place_id, _locked_workitem_id} when state in [:free] ->
        {place_id, token_id}
      end)

    token_table
    |> :ets.select(match_spec)
    |> Enum.each(fn {place_id, token_id} ->
      do_offer_token(state, {place_id, token_id})
    end)
  end

  defp do_offer_token(%__MODULE__{} = state, {place_id, token_id}) do
    %{
      application: application,
      workflow_id: workflow_id,
      case_id: case_id
    } = state

    state
    |> workflow_server()
    |> WorkflowMetal.Workflow.Workflow.fetch_transitions(place_id, :out)
    |> Enum.each(fn transition ->
      {:ok, task_pid} =
        WorkflowMetal.Task.Supervisor.open_task(
          application,
          workflow_id,
          case_id,
          transition.id
        )

      GenServer.cast(task_pid, {:offer_token, place_id, token_id})
    end)
  end

  defp withdraw_tokens(%__MODULE__{} = _state) do
    # TODO:
    # withdraw_token(transition_pid, {place_id, token_id})
  end

  defp workflow_server(%__MODULE__{} = state) do
    %{application: application, workflow_id: workflow_id} = state

    WorkflowMetal.Workflow.Workflow.via_name(application, workflow_id)
  end
end
