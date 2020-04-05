defmodule WorkflowMetal.Case.Case do
  @moduledoc """
  `GenServer` process to present a workflow case.

  ## Storage
  The data of `:token_table` is stored in ETS in the following format:
      {token_id, token_state, place_id, locked_by_task_id}
  """

  alias WorkflowMetal.Storage.Schema

  use GenServer

  defstruct [
    :application,
    :case_schema,
    :start_place,
    :end_place,
    :token_table,
    free_token_ids: MapSet.new()
  ]

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type case_schema :: WorkflowMetal.Storage.Schema.Case.t()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()
  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()

  @type options :: [name: term(), case_schema: case_schema]

  @doc false
  @spec start_link(workflow_identifier, options) :: GenServer.on_start()
  def start_link(workflow_identifier, options) do
    name = Keyword.fetch!(options, :name)
    case_schema = Keyword.fetch!(options, :case_schema)

    GenServer.start_link(__MODULE__, {workflow_identifier, case_schema}, name: name)
  end

  @doc false
  @spec name({workflow_id, case_id}) :: term
  def name({workflow_id, case_id}) do
    {__MODULE__, {workflow_id, case_id}}
  end

  @doc false
  @spec via_name(application, {workflow_id, case_id}) :: term
  def via_name(application, {workflow_id, case_id}) do
    WorkflowMetal.Registration.via_tuple(
      application,
      name({workflow_id, case_id})
    )
  end

  @doc """
  Issue tokens.
  """
  @spec issue_tokens(GenServer.server(), nonempty_list(token_params)) ::
          {:ok, [token_schema]}
  def issue_tokens(case_server, [_ | _] = token_params_list) do
    GenServer.call(case_server, {:issue_tokens, token_params_list})
  end

  @doc """
  Lock tokens.
  """
  @spec lock_tokens(GenServer.server(), [token_id], task_id) ::
          :ok | {:error, :tokens_not_available}
  def lock_tokens(case_server, [_ | _] = token_ids, task_id) do
    GenServer.call(case_server, {:lock_tokens, token_ids, task_id})
  end

  @doc """
  Consume tokens.
  """
  @spec consume_tokens(GenServer.server(), [token_id], task_id) ::
          :ok | {:error, :tokens_not_available}
  def consume_tokens(case_server, [_ | _] = token_ids, task_id) do
    GenServer.call(case_server, {:consume_tokens, token_ids, task_id})
  end

  # Server (callbacks)

  @impl true
  def init({{application, _workflow_id}, case_schema}) do
    token_table = :ets.new(:token_table, [:set, :private])

    {
      :ok,
      %__MODULE__{
        application: application,
        case_schema: case_schema,
        token_table: token_table
      },
      {:continue, :rebuild_from_storage}
    }
  end

  @impl true
  def handle_continue(:rebuild_from_storage, %__MODULE__{} = state) do
    with(
      {:ok, state} <- rebuild_tokens(state),
      {:ok, state} <- fetch_start_and_end_places(state)
    ) do
      {:noreply, state, {:continue, :activate_case}}
    end
  end

  @impl true
  def handle_continue(
        :activate_case,
        %__MODULE__{case_schema: %Schema.Case{state: :created}} = state
      ) do
    {:ok, state} = do_activate_case(state)
    {:noreply, state, {:continue, :offer_tokens}}
  end

  def handle_continue(:activate_case, state), do: {:noreply, state}

  @impl true
  def handle_continue(:offer_tokens, %__MODULE__{} = state) do
    :ok = do_offer_tokens(state)
    {:noreply, state}
  end

  @impl true
  def handle_continue(:fire_transitions, %__MODULE__{} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_call({:issue_tokens, token_params_list}, _from, %__MODULE__{} = state) do
    with({:ok, tokens, state} <- do_issue_tokens(token_params_list, state)) do
      {:reply, {:ok, tokens}, state, {:continue, :offer_tokens}}
    end
  end

  @impl true
  def handle_call({:lock_tokens, token_ids, task_id}, _from, %__MODULE__{} = state) do
    with(
      {:ok, state} <- do_lock_tokens(state, MapSet.new(token_ids), task_id),
      {:ok, _state} <- withdraw_tokens(state, task_id)
    ) do
      {:reply, :ok, state}
    else
      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(
        {:consume_tokens, token_ids, task_id},
        _from,
        %__MODULE__{} = state
      ) do
    with({:ok, state} <- do_consume_tokens(token_ids, task_id, state)) do
      {:reply, :ok, state}
    end
  end

  defp rebuild_tokens(%__MODULE__{} = state) do
    %{
      application: application,
      case_schema: %Schema.Case{
        id: case_id
      },
      token_table: token_table
    } = state

    with({:ok, tokens} <- WorkflowMetal.Storage.fetch_tokens(application, case_id, [:free])) do
      free_token_ids =
        MapSet.new(tokens, fn token ->
          :ok = insert_token(token_table, token)
          token.id
        end)

      {
        :ok,
        Map.update!(
          state,
          :free_token_ids,
          &MapSet.union(&1, MapSet.new(free_token_ids))
        )
      }
    end
  end

  defp fetch_start_and_end_places(%__MODULE__{} = state) do
    %{
      application: application,
      case_schema: %Schema.Case{
        workflow_id: workflow_id
      }
    } = state

    {:ok, {start_place, end_place}} =
      WorkflowMetal.Storage.fetch_edge_places(application, workflow_id)

    {:ok, %{state | start_place: start_place, end_place: end_place}}
  end

  defp insert_token(token_table, %Schema.Token{} = token) do
    %{
      id: token_id,
      state: state,
      place_id: place_id,
      locked_by_task_id: locked_by_task_id
    } = token

    true = :ets.insert(token_table, {token_id, state, place_id, locked_by_task_id})

    :ok
  end

  defp do_activate_case(%__MODULE__{} = state) do
    %{
      application: application,
      start_place: %Schema.Place{
        id: start_place_id
      },
      case_schema: case_schema,
      free_token_ids: free_token_ids
    } = state

    {
      :ok,
      %Schema.Case{
        id: case_id,
        workflow_id: workflow_id
      } = case_schema
    } = WorkflowMetal.Storage.activate_case(application, case_schema.id)

    genesis_token_params = %Schema.Token.Params{
      workflow_id: workflow_id,
      case_id: case_id,
      place_id: start_place_id,
      produced_by_task_id: :genesis,
      payload: nil
    }

    {:ok, token_schema} = do_issue_token(genesis_token_params, state)

    {
      :ok,
      %{
        state
        | case_schema: case_schema,
          free_token_ids: MapSet.put(free_token_ids, token_schema.id)
      }
    }
  end

  defp do_issue_token(token_params, %__MODULE__{} = state) do
    %{
      application: application,
      token_table: token_table
    } = state

    {:ok, token_schema} = WorkflowMetal.Storage.issue_token(application, token_params)

    :ok = insert_token(token_table, token_schema)

    {:ok, token_schema}
  end

  defp do_issue_tokens(token_params_list, %__MODULE__{} = state) do
    new_tokens =
      Enum.map(token_params_list, fn token_schema ->
        {:ok, token_schema} = do_issue_token(token_schema, state)

        token_schema
      end)

    {
      :ok,
      new_tokens,
      Map.update!(
        state,
        :free_token_ids,
        fn free_token_ids ->
          MapSet.union(
            free_token_ids,
            MapSet.new(new_tokens, fn new_token -> new_token.id end)
          )
        end
      )
    }
  end

  defp do_offer_tokens(%__MODULE__{} = state) do
    %{token_table: token_table} = state

    match_spec = [{{:"$1", :free, :"$2", :_}, [], [{{:"$2", :"$1"}}]}]

    token_table
    |> :ets.select(match_spec)
    |> Enum.each(fn {place_id, token_id} ->
      do_offer_token(state, place_id, token_id)
    end)

    :ok
  end

  defp do_offer_token(%__MODULE__{} = state, place_id, token_id) do
    %{application: application} = state

    {:ok, transitions} = WorkflowMetal.Storage.fetch_transitions(application, place_id, :out)

    transitions
    |> Stream.map(fn transition ->
      fetch_or_create_task(state, transition)
    end)
    |> Stream.each(fn {:ok, task} ->
      {:ok, task_server} = WorkflowMetal.Task.Supervisor.open_task(application, task.id)

      WorkflowMetal.Task.Task.offer_token(task_server, place_id, token_id)
    end)
    |> Stream.run()
  end

  defp fetch_or_create_task(%__MODULE__{} = state, transition) do
    %{
      application: application,
      case_schema: %Schema.Case{
        id: case_id,
        workflow_id: workflow_id
      }
    } = state

    %{id: transition_id} = transition

    case WorkflowMetal.Storage.fetch_task(application, case_id, transition_id) do
      {:ok, task} ->
        {:ok, task}

      {:error, _} ->
        task_params = %Schema.Task.Params{
          workflow_id: workflow_id,
          case_id: case_id,
          transition_id: transition_id
        }

        {:ok, _} = WorkflowMetal.Storage.create_task(application, task_params)
    end
  end

  @state_position 2
  @locked_by_task_id_position 4
  defp do_lock_tokens(%__MODULE__{} = state, token_ids, task_id) do
    %{
      application: application,
      token_table: token_table,
      free_token_ids: free_token_ids
    } = state

    if MapSet.subset?(token_ids, free_token_ids) do
      Enum.each(token_ids, fn token_id ->
        :ets.update_element(token_table, token_id, [
          {@state_position, :locked},
          {@locked_by_task_id_position, task_id}
        ])

        {:ok, _token_schema} = WorkflowMetal.Storage.lock_token(application, token_id, task_id)
      end)

      free_token_ids = MapSet.difference(free_token_ids, token_ids)

      {:ok, %{state | free_token_ids: free_token_ids}}
    else
      {:error, :tokens_not_available}
    end
  end

  defp do_consume_tokens(token_ids, task_id, state) do
    %{
      application: application
    } = state

    {:ok, _tokens} = WorkflowMetal.Storage.consume_tokens(application, token_ids, task_id)

    {:ok, state}
  end

  defp withdraw_tokens(%__MODULE__{} = state, _except_task_id) do
    # TODO:
    # withdraw_token(transition_pid, {place_id, token_id})
    {:ok, state}
  end
end
