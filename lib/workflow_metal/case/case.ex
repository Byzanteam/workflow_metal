defmodule WorkflowMetal.Case.Case do
  @moduledoc """
  `GenStateMachine` process to present a workflow case.

  ## Storage
  The data of `:token_table` is stored in ETS in the following format:
      {token_id, token_schema, token_state, locked_by_task_id, consumed_by_task_id}

  ## State

  ```
  created+------->active+------->finished
      +              +
      |              |
      |              v
      +---------->canceled
  ```
  """

  alias WorkflowMetal.Storage.Schema

  require Logger

  use GenStateMachine,
    callback_mode: [:handle_event_function, :state_enter],
    restart: :temporary

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

  @type options :: [
          name: term(),
          case_schema: case_schema
        ]

  @doc false
  @spec start_link(workflow_identifier, options) :: :gen_statem.start_ret()
  def start_link(workflow_identifier, options) do
    name = Keyword.fetch!(options, :name)
    case_schema = Keyword.fetch!(options, :case_schema)

    GenStateMachine.start_link(__MODULE__, {workflow_identifier, case_schema}, name: name)
  end

  @doc false
  @spec name({workflow_id, case_id}) :: term
  def name({workflow_id, case_id}) do
    {__MODULE__, {workflow_id, case_id}}
  end

  @doc false
  @spec name(case_schema) :: term
  def name(%Schema.Case{} = case_schema) do
    %{
      id: case_id,
      workflow_id: workflow_id
    } = case_schema

    name({workflow_id, case_id})
  end

  @doc false
  @spec via_name(application, {workflow_id, case_id}) :: term
  def via_name(application, {workflow_id, case_id}) do
    WorkflowMetal.Registration.via_tuple(
      application,
      name({workflow_id, case_id})
    )
  end

  @doc false
  @spec via_name(application, case_schema) :: term
  def via_name(application, %Schema.Case{} = case_schema) do
    WorkflowMetal.Registration.via_tuple(
      application,
      name(case_schema)
    )
  end

  @doc """
  Issue tokens.
  """
  @spec issue_tokens(:gen_statem.server_ref(), nonempty_list(token_params)) ::
          {:ok, [token_schema]}
  def issue_tokens(case_server, [_ | _] = token_params_list) do
    GenStateMachine.call(case_server, {:issue_tokens, token_params_list})
  end

  @doc """
  Lock tokens.
  """
  @spec lock_tokens(:gen_statem.server_ref(), [token_id], task_id) ::
          {:ok, nonempty_list(token_schema)} | {:error, :tokens_not_available}
  def lock_tokens(case_server, [_ | _] = token_ids, task_id) do
    GenStateMachine.call(case_server, {:lock_tokens, token_ids, task_id})
  end

  @doc """
  Consume tokens.
  """
  @spec consume_tokens(:gen_statem.server_ref(), [token_id], task_id) ::
          {:ok, nonempty_list(token_schema)} | {:error, :tokens_not_available}
  def consume_tokens(case_server, [_ | _] = token_ids, task_id) do
    GenStateMachine.call(case_server, {:consume_tokens, token_ids, task_id})
  end

  @doc """
  Request free tokens when a task restore from storage.
  """
  @spec request_free_tokens(:gen_statem.server_ref(), task_id) :: :ok
  def request_free_tokens(case_server, task_id) do
    GenStateMachine.cast(case_server, {:request_free_tokens, task_id})
  end

  # Server (callbacks)

  @impl true
  def init({{application, _workflow_id}, case_schema}) do
    %{
      state: state
    } = case_schema

    if state in [:canceled, :finished] do
      {:stop, :normal}
    else
      {
        :ok,
        state,
        %__MODULE__{
          application: application,
          case_schema: case_schema,
          token_table: :ets.new(:token_table, [:set, :private])
        }
      }
    end
  end

  @impl GenStateMachine
  # init
  def handle_event(:enter, state, state, %__MODULE__{}) do
    case state do
      :created ->
        {
          :keep_state_and_data,
          {:state_timeout, 0, :restore_from_created}
        }

      :active ->
        {
          :keep_state_and_data,
          {:state_timeout, 0, :restore_from_active}
        }
    end
  end

  @impl GenStateMachine
  def handle_event(:enter, old_state, state, %__MODULE__{} = data) do
    case {old_state, state} do
      {:created, :active} ->
        Logger.debug(fn -> "#{describe(data)} is activated." end)

        {:ok, data} = update_case(:active, data)
        {:keep_state, data}

      {:active, :finished} ->
        Logger.debug(fn -> "#{describe(data)} is finished." end)

        {:keep_state, data}

      {_, :canceled} ->
        Logger.debug(fn -> "#{describe(data)} is canceled." end)

        {:ok, data} = update_case(:canceled, data)
        {:keep_state, data}
    end
  end

  @impl GenStateMachine
  def handle_event(:state_timeout, :restore_from_created, :created, %__MODULE__{} = data) do
    {:ok, data} = fetch_edge_places(data)
    {:ok, data} = do_activate_case(data)

    {
      :next_state,
      :active,
      data,
      {:next_event, :internal, :offer_tokens}
    }
  end

  @impl GenStateMachine
  def handle_event(:state_timeout, :restore_from_active, :active, %__MODULE__{} = data) do
    {:ok, data} = rebuild_tokens(data)
    {:ok, data} = fetch_edge_places(data)
    {:ok, data} = do_start_executing_tasks(data)

    {
      :keep_state,
      data,
      {:next_event, :internal, :offer_tokens}
    }
  end

  @impl GenStateMachine
  def handle_event(:internal, :offer_tokens, :active, %__MODULE__{} = data) do
    {:ok, data} = do_offer_tokens(data)

    {
      :keep_state,
      data,
      {:next_event, :internal, :finish}
    }
  end

  @impl GenStateMachine
  def handle_event(
        :internal,
        {:withdraw_tokens, locked_token_schemas, except_task_id},
        :active,
        %__MODULE__{} = data
      ) do
    {:ok, data} = do_withdraw_tokens(locked_token_schemas, except_task_id, data)

    {:keep_state, data}
  end

  @impl GenStateMachine
  def handle_event(:internal, :finish, :active, %__MODULE__{} = data) do
    with(
      {:finished, data} <- case_finishment(data),
      {:ok, data} <- do_finish_case(data)
    ) do
      {
        :next_state,
        :finished,
        data,
        {:next_event, :internal, :stop}
      }
    else
      _ ->
        :keep_state_and_data
    end
  end

  @impl GenStateMachine
  def handle_event(:internal, :stop, state, %__MODULE__{} = data)
      when state in [:canceled, :finished] do
    {:stop, :normal, data}
  end

  @impl GenStateMachine
  def handle_event(
        {:call, from},
        {:lock_tokens, token_ids, task_id},
        :active,
        %__MODULE__{} = data
      ) do
    case do_lock_tokens(MapSet.new(token_ids), task_id, data) do
      {:ok, locked_token_schemas, data} ->
        Logger.debug(fn ->
          "#{describe(data)}: tokens(#{token_ids |> Enum.join(", ")}) have been locked by the task(#{
            task_id
          })"
        end)

        {
          :keep_state,
          data,
          [
            {:reply, from, {:ok, locked_token_schemas}},
            {:next_event, :internal, {:withdraw_tokens, locked_token_schemas, task_id}}
          ]
        }

      error ->
        {
          :keep_state,
          data,
          {:reply, from, error}
        }
    end
  end

  @impl GenStateMachine
  def handle_event(
        {:call, from},
        {:consume_tokens, token_ids, task_id},
        :active,
        %__MODULE__{} = data
      ) do
    case do_consume_tokens(token_ids, task_id, data) do
      {:ok, tokens, data} ->
        Logger.debug(fn ->
          "#{describe(data)}: tokens(#{token_ids |> Enum.join(", ")}) have been consumed by the task(#{
            task_id
          })"
        end)

        {
          :keep_state,
          data,
          {:reply, from, {:ok, tokens}}
        }

      error ->
        {
          :keep_state,
          data,
          {:reply, from, error}
        }
    end
  end

  @impl GenStateMachine
  def handle_event(
        {:call, from},
        {:issue_tokens, token_params_list},
        :active,
        %__MODULE__{} = data
      ) do
    {:ok, tokens, data} = do_issue_tokens(token_params_list, data)

    Logger.debug(fn ->
      "#{describe(data)}: tokens(#{tokens |> Enum.map(& &1.id) |> Enum.join(", ")}) have been issued"
    end)

    {
      :keep_state,
      data,
      [
        {:reply, from, {:ok, tokens}},
        {:next_event, :internal, :offer_tokens}
      ]
    }
  end

  @impl GenStateMachine
  def handle_event({:call, from}, _event_content, _state, %__MODULE__{}) do
    {:keep_state_and_data, {:reply, from, {:error, :case_not_available}}}
  end

  @impl GenStateMachine
  def handle_event(:cast, {:request_free_tokens, task_id}, :active, %__MODULE__{} = data) do
    {:ok, data} = do_request_free_tokens(task_id, data)

    {:keep_state, data}
  end

  @impl GenStateMachine
  def format_status(_reason, [_pdict, state, data]) do
    {:state, %{current_state: state, data: data}}
  end

  defp rebuild_tokens(%__MODULE__{} = data) do
    %{
      application: application,
      case_schema: %Schema.Case{
        id: case_id
      },
      token_table: token_table
    } = data

    with(
      {:ok, tokens} <- WorkflowMetal.Storage.fetch_tokens(application, case_id, [:free, :locked])
    ) do
      free_token_ids =
        Enum.reduce(tokens, MapSet.new(), fn
          %Schema.Token{state: :free} = token, acc ->
            :ok = insert_token(token, token_table)
            MapSet.put(acc, token.id)

          %Schema.Token{state: :locked} = token, acc ->
            :ok = insert_token(token, token_table)
            acc
        end)

      {
        :ok,
        Map.update!(
          data,
          :free_token_ids,
          &MapSet.union(&1, MapSet.new(free_token_ids))
        )
      }
    end
  end

  defp fetch_edge_places(%__MODULE__{} = data) do
    %{
      application: application,
      case_schema: %Schema.Case{
        workflow_id: workflow_id
      }
    } = data

    {:ok, {start_place, end_place}} =
      WorkflowMetal.Storage.fetch_edge_places(application, workflow_id)

    {:ok, %{data | start_place: start_place, end_place: end_place}}
  end

  defp update_case(state_and_options, %__MODULE__{} = data) do
    %{
      application: application,
      case_schema: case_schema
    } = data

    {:ok, case_schema} =
      WorkflowMetal.Storage.update_case(
        application,
        case_schema.id,
        state_and_options
      )

    {:ok, %{data | case_schema: case_schema}}
  end

  defp do_activate_case(%__MODULE__{} = data) do
    %{
      start_place: %Schema.Place{
        id: start_place_id
      },
      case_schema: %Schema.Case{
        id: case_id,
        workflow_id: workflow_id
      },
      free_token_ids: free_token_ids
    } = data

    genesis_token_params = %Schema.Token.Params{
      workflow_id: workflow_id,
      place_id: start_place_id,
      case_id: case_id,
      produced_by_task_id: :genesis,
      payload: nil
    }

    {:ok, token_schema} = do_issue_token(genesis_token_params, data)

    {
      :ok,
      %{data | free_token_ids: MapSet.put(free_token_ids, token_schema.id)}
    }
  end

  defp do_start_executing_tasks(%__MODULE__{} = data) do
    %{
      application: application,
      case_schema: %Schema.Case{
        id: case_id
      }
    } = data

    {:ok, tasks} =
      WorkflowMetal.Storage.fetch_tasks(
        application,
        case_id,
        [:executing]
      )

    Enum.each(tasks, fn task ->
      {:ok, _pid} = WorkflowMetal.Task.Supervisor.open_task(application, task.id)
    end)

    {:ok, data}
  end

  defp do_issue_token(token_params, %__MODULE__{} = data) do
    %{
      application: application,
      token_table: token_table
    } = data

    {:ok, token_schema} = WorkflowMetal.Storage.issue_token(application, token_params)

    :ok = insert_token(token_schema, token_table)

    {:ok, token_schema}
  end

  defp insert_token(%Schema.Token{} = token, token_table) do
    %{
      id: token_id,
      state: state,
      locked_by_task_id: locked_by_task_id,
      consumed_by_task_id: consumed_by_task_id
    } = token

    true =
      :ets.insert(
        token_table,
        {token_id, token, state, locked_by_task_id, consumed_by_task_id}
      )

    :ok
  end

  defp do_issue_tokens(token_params_list, %__MODULE__{} = data) do
    new_tokens =
      Enum.map(token_params_list, fn token_schema ->
        {:ok, token_schema} = do_issue_token(token_schema, data)

        token_schema
      end)

    {
      :ok,
      new_tokens,
      Map.update!(
        data,
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

  defp do_offer_tokens(%__MODULE__{} = data) do
    %{
      token_table: token_table
    } = data

    token_table
    |> :ets.select([{{:_, :"$1", :free, :_, :_}, [], [:"$1"]}])
    |> Enum.each(fn token_schema ->
      do_offer_token(token_schema, data)
    end)

    {:ok, data}
  end

  defp do_offer_token(%Schema.Token{} = token_schema, %__MODULE__{} = data) do
    %{
      application: application
    } = data

    {:ok, transitions} =
      WorkflowMetal.Storage.fetch_transitions(
        application,
        token_schema.place_id,
        :out
      )

    transitions
    |> Stream.map(fn transition ->
      fetch_or_create_task(transition, data)
    end)
    |> Stream.each(fn {:ok, task} ->
      {:ok, task_server} = WorkflowMetal.Task.Supervisor.open_task(application, task.id)

      :ok = WorkflowMetal.Task.Task.offer_token(task_server, token_schema)

      Logger.debug(fn ->
        "#{describe(data)}: offers a token(#{token_schema.id}) to the task(#{task.id})"
      end)
    end)
    |> Stream.run()
  end

  defp fetch_or_create_task(transition, %__MODULE__{} = data) do
    %{id: transition_id} = transition

    case fetch_available_task(transition_id, data) do
      {:ok, task} ->
        {:ok, task}

      {:error, _} ->
        %{
          application: application,
          case_schema: %Schema.Case{
            id: case_id,
            workflow_id: workflow_id
          }
        } = data

        task_params = %Schema.Task.Params{
          workflow_id: workflow_id,
          case_id: case_id,
          transition_id: transition_id
        }

        {:ok, _} = WorkflowMetal.Storage.create_task(application, task_params)
    end
  end

  defp do_lock_tokens(token_ids, task_id, %__MODULE__{} = data) do
    %{
      application: application,
      token_table: token_table,
      free_token_ids: free_token_ids
    } = data

    if MapSet.subset?(token_ids, free_token_ids) do
      locked_token_schemas =
        Enum.map(token_ids, fn token_id ->
          :ets.update_element(token_table, token_id, [
            {3, :locked},
            {4, task_id}
          ])

          {:ok, token_schema} = WorkflowMetal.Storage.lock_token(application, token_id, task_id)

          token_schema
        end)

      free_token_ids = MapSet.difference(free_token_ids, token_ids)

      {:ok, locked_token_schemas, %{data | free_token_ids: free_token_ids}}
    else
      {:error, :tokens_not_available}
    end
  end

  defp do_consume_tokens(token_ids, task_id, %__MODULE__{} = data) do
    %{
      application: application
    } = data

    with(
      {:ok, tokens} <- WorkflowMetal.Storage.consume_tokens(application, token_ids, task_id)
    ) do
      {:ok, tokens, data}
    end
  end

  defp case_finishment(%__MODULE__{} = data) do
    %{
      end_place: %Schema.Place{
        id: end_place_id
      },
      token_table: token_table,
      free_token_ids: free_token_ids
    } = data

    with(
      [free_token_id] <- MapSet.to_list(free_token_ids),
      match_spec = [{{free_token_id, :"$1", :free, :_, :_}, [], [:"$1"]}],
      [%Schema.Token{place_id: ^end_place_id}] <- :ets.select(token_table, match_spec)
    ) do
      {:finished, data}
    else
      _ ->
        {:active, data}
    end
  end

  defp do_finish_case(%__MODULE__{} = data) do
    %{
      token_table: token_table,
      free_token_ids: free_token_ids
    } = data

    [free_token_id] = MapSet.to_list(free_token_ids)
    true = :ets.update_element(token_table, free_token_id, [{3, :consumed}])
    {:ok, data} = update_case(:finished, data)

    {:ok, data}
  end

  defp do_withdraw_tokens(locked_token_schemas, except_task_id, %__MODULE__{} = data) do
    Enum.each(locked_token_schemas, fn locked_token ->
      :ok = do_withdraw_token(locked_token, except_task_id, data)
    end)

    {:ok, data}
  end

  defp do_withdraw_token(%Schema.Token{} = token_schema, except_task_id, %__MODULE__{} = data) do
    %{
      application: application,
      token_table: token_table
    } = data

    token_table
    |> :ets.select([{{token_schema.id, :"$1", :locked, :_, :_}, [], [:"$1"]}])
    |> Enum.flat_map(fn token_schema ->
      {:ok, transitions} =
        WorkflowMetal.Storage.fetch_transitions(
          application,
          token_schema.place_id,
          :out
        )

      transitions
    end)
    |> Stream.map(fn transition ->
      fetch_available_task(transition.id, data)
    end)
    |> Stream.each(fn
      {:ok, %Schema.Task{id: task_id} = task} when task_id !== except_task_id ->
        task_server_name = WorkflowMetal.Task.Task.name(task)

        case WorkflowMetal.Registration.whereis_name(application, task_server_name) do
          :undefined ->
            :skip

          task_server ->
            WorkflowMetal.Task.Task.withdraw_token(task_server, token_schema.id)
        end

      {:ok, _task} ->
        # skip the non-running task server
        :skip

      {:error, _reason} ->
        :skip
    end)
    |> Stream.run()

    :ok
  end

  defp fetch_available_task(transition_id, %__MODULE__{} = data) do
    %{
      application: application,
      case_schema: %Schema.Case{
        id: case_id
      }
    } = data

    WorkflowMetal.Storage.fetch_available_task(application, case_id, transition_id)
  end

  defp do_request_free_tokens(task_id, %__MODULE__{} = data) do
    %{
      application: application,
      token_table: token_table
    } = data

    with(
      {:ok, task_schema} <- WorkflowMetal.Storage.fetch_task(application, task_id),
      %Schema.Task{state: :started} <- task_schema,
      task_server_name = WorkflowMetal.Task.Task.name(task_schema),
      task_server when task_server !== :undefined <-
        WorkflowMetal.Registration.whereis_name(application, task_server_name)
    ) do
      token_table
      |> :ets.select([
        {
          {:_, :"$1", :"$2", :"$3", :_},
          [
            {
              :orelse,
              {:andalso, {:"=:=", :"$2", :locked}, {:"=:=", :"$3", task_id}},
              {:"=:=", :"$2", :free}
            }
          ],
          [:"$1"]
        }
      ])
      |> Enum.each(fn token_schema ->
        :ok = WorkflowMetal.Task.Task.offer_token(task_server, token_schema)
      end)
    end

    {:ok, data}
  end

  defp describe(%__MODULE__{} = data) do
    %{
      case_schema: %Schema.Case{
        id: case_id,
        workflow_id: workflow_id
      }
    } = data

    "Case<#{case_id}@#{workflow_id}>"
  end
end
