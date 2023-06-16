defmodule WorkflowMetal.Case.Case do
  @moduledoc """
  `GenServer` process to present a workflow case.

  ## Storage
  The data of `:token_table` is stored in ETS in the following format:
      {token_id, token_schema, token_state, place_id, locked_by_task_id, consumed_by_task_id}

  ## State

  ```
  created+------->active+------->finished
      +              +
      |              |
      |              v
      +---------->terminated
  ```

  ## Restore

  Restore a case while offering tokens.
  """

  use GenServer, restart: :transient
  use TypedStruct

  alias WorkflowMetal.Storage.Schema
  alias WorkflowMetal.Utils.ETS, as: ETSUtil

  require Logger

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Supervisor.workflow_identifier()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type case_schema :: WorkflowMetal.Storage.Schema.Case.t()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type place_schema :: WorkflowMetal.Storage.Schema.Place.t()
  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()
  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()

  typedstruct do
    field :application, application
    field :case_schema, case_schema
    field :state, WorkflowMetal.Storage.Schema.Case.state()
    field :start_place, place_schema
    field :end_place, place_schema
    field :token_table, :ets.tid()
    field :free_token_ids, MapSet.t(), default: MapSet.new()
  end

  @type options :: [
          name: term(),
          case_schema: case_schema
        ]

  @doc false
  @spec start_link(workflow_identifier, options) :: :gen_statem.start_ret()
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
  terminate a case.
  """
  @spec terminate(:gen_statem.server_ref()) :: :ok
  def terminate(case_server) do
    GenServer.cast(case_server, :terminate)
  end

  @doc """
  Issue tokens.
  """
  @spec issue_tokens(:gen_statem.server_ref(), nonempty_list(token_schema)) ::
          {:ok, nonempty_list(token_schema)}
  def issue_tokens(case_server, [_ | _] = token_schema_list) do
    GenServer.call(case_server, {:issue_tokens, token_schema_list})
  end

  @doc """
  Lock tokens.
  """
  @spec lock_tokens(:gen_statem.server_ref(), [token_id], task_id) ::
          {:ok, nonempty_list(token_schema)}
          | {:error, :tokens_not_available}
  def lock_tokens(case_server, [_ | _] = token_ids, task_id) do
    GenServer.call(case_server, {:lock_tokens, token_ids, task_id})
  end

  @doc """
  Consume tokens.
  """
  @spec consume_tokens(:gen_statem.server_ref(), task_id) ::
          {:ok, nonempty_list(token_schema)} | {:error, :tokens_not_available}
  def consume_tokens(case_server, task_id) do
    GenServer.call(case_server, {:consume_tokens, task_id})
  end

  @doc """
  Offer `:free` and `:locked` tokens to the task.

  eg: request `:free` and `:locked` tokens when a task restore from storage.
  """
  @spec offer_tokens_to_task(:gen_statem.server_ref(), task_id) :: {:ok, [token_schema]}
  def offer_tokens_to_task(case_server, task_id) do
    GenServer.call(case_server, {:offer_tokens_to_task, task_id})
  end

  @doc """
  Free tokens that locked by the task.

  eg: free `:locked` tokens when a task has been abandoned.
  """
  @spec free_tokens_from_task(:gen_statem.server_ref(), task_id) :: :ok
  def free_tokens_from_task(case_server, task_id) do
    GenServer.call(case_server, {:free_tokens_from_task, task_id})
  end

  @doc """
  Free tokens that locked by the task.

  eg: free `:locked` tokens when a task has been abandoned.
  """
  @spec fetch_locked_tokens_from_task(:gen_statem.server_ref(), task_id) :: {:ok, [token_schema]}
  def fetch_locked_tokens_from_task(case_server, task_id) do
    GenServer.call(case_server, {:fetch_locked_tokens_from_task, task_id})
  end

  # Server (callbacks)

  @impl true
  def init({{application, _workflow_id}, case_schema}) do
    case case_schema.state do
      state when state in [:terminated, :finished] ->
        {:stop, :case_not_available}

      state ->
        {
          :ok,
          %__MODULE__{
            application: application,
            case_schema: case_schema,
            state: state,
            token_table: :ets.new(:token_table, [:set, :private])
          },
          {:continue, :after_start}
        }
    end
  end

  @impl GenServer
  def handle_continue(:after_start, %{state: :created} = data) do
    data =
      data
      |> fetch_edge_places()
      |> do_activate_case()
      |> update_case(%{state: :active})

    {:noreply, data, {:continue, :offer_tokens}}
  end

  @impl GenServer
  def handle_continue(:after_start, %{state: :active} = data) do
    data =
      data
      |> fetch_edge_places()
      |> fetch_unconsumed_tokens()

    {:noreply, data, {:continue, :offer_tokens}}
  end

  @impl GenServer
  def handle_continue(:offer_tokens, %{state: :active} = data) do
    data = do_offer_tokens(data)

    {:noreply, data, {:continue, :try_finish}}
  end

  @impl GenServer
  def handle_continue({:offer_tokens, tokens}, %{state: :active} = data) do
    data = do_offer_tokens(tokens, data)

    {:noreply, data, {:continue, :try_finish}}
  end

  @impl GenServer
  def handle_continue(:try_finish, %{state: :active} = data) do
    case case_finishment(data) do
      {:finished, data} ->
        data =
          data
          |> do_finish_case()
          |> update_case(%{state: :finished})

        {:noreply, data, {:continue, :stop_server}}

      _error ->
        {:noreply, data}
    end
  end

  @impl GenServer
  def handle_continue({:revoke_tokens, locked_token_schemas, except_task_id}, %__MODULE__{state: :active} = data) do
    data = do_revoke_tokens(locked_token_schemas, except_task_id, data)

    {:noreply, data}
  end

  @impl GenServer
  def handle_continue(:stop_server, data) do
    {:stop, :normal, data}
  end

  @impl GenServer
  def handle_call({:lock_tokens, token_ids, task_id}, _from, %{state: :active} = data) do
    case do_lock_tokens(MapSet.new(token_ids), task_id, data) do
      {:ok, locked_token_schemas, data} ->
        Logger.debug(fn ->
          "#{describe(data)}: tokens(#{Enum.join(token_ids, ", ")}) have been locked by the task(#{task_id})"
        end)

        {:reply, {:ok, locked_token_schemas}, data}

      {:error, _reason} = error ->
        {:reply, error, data}
    end
  end

  @impl GenServer
  def handle_call({:consume_tokens, task_id}, _from, %{state: :active} = data) do
    {tokens, data} = do_consume_tokens(task_id, data)

    Logger.debug(fn ->
      "#{describe(data)}: tokens(#{Enum.map_join(tokens, ", ", & &1.id)}) have been consumed by the task(#{task_id})"
    end)

    {:reply, {:ok, tokens}, data, {:continue, {:revoke_tokens, tokens, task_id}}}
  end

  @impl GenServer
  def handle_call({:issue_tokens, token_schema_list}, _from, %{state: :active} = data) do
    {tokens, data} = do_issue_tokens(token_schema_list, data)

    Logger.debug(fn ->
      "#{describe(data)}: tokens(#{Enum.map_join(tokens, ", ", & &1.id)}) have been issued"
    end)

    {:reply, {:ok, tokens}, data, {:continue, {:offer_tokens, tokens}}}
  end

  @impl GenServer
  def handle_call({:offer_tokens_to_task, task_id}, _from, %{state: :active} = data) do
    {tokens, data} = do_offer_tokens_to_task(task_id, data)

    {:reply, {:ok, tokens}, data}
  end

  @impl GenServer
  def handle_call({:fetch_locked_tokens_from_task, task_id}, _from, %{state: :active} = data) do
    tokens = do_fetch_locked_tokens_from_task(task_id, data)

    {:reply, {:ok, tokens}, data}
  end

  @impl GenServer
  def handle_call(_msg, _from, %{} = data) do
    {:reply, {:error, :case_not_available}, data}
  end

  @impl GenServer
  def handle_cast({:free_tokens_from_task, task_id}, %{state: :active} = data) do
    token_ids = find_locked_token_ids(task_id, data)

    {:ok, tokens} = WorkflowMetal.Storage.unlock_tokens(data.application, token_ids)

    Logger.debug(fn ->
      "#{describe(data)}: tokens(#{Enum.map_join(tokens, ", ", & &1.id)}) have been freed by the task(#{task_id})"
    end)

    {
      :noreply,
      data,
      {:continue, {:offer_tokens, tokens}}
    }
  end

  @impl GenServer
  def handle_cast(:terminate, %__MODULE__{state: state} = data) when state in [:created, :active] do
    data =
      data
      |> force_abandon_tasks()
      |> update_case(%{state: :terminated})

    {:noreply, data, {:continue, :stop_server}}
  end

  @spec fetch_unconsumed_tokens(t()) :: t()
  defp fetch_unconsumed_tokens(%__MODULE__{} = data) do
    %{
      application: application,
      case_schema: %Schema.Case{
        id: case_id
      }
    } = data

    {:ok, tokens} = WorkflowMetal.Storage.fetch_unconsumed_tokens(application, case_id)

    free_token_ids =
      Enum.reduce(tokens, MapSet.new(), fn
        %Schema.Token{state: :free} = token, acc ->
          {:ok, _data} = upsert_ets_token(token, data)
          MapSet.put(acc, token.id)

        %Schema.Token{state: :locked} = token, acc ->
          {:ok, _data} = upsert_ets_token(token, data)
          acc
      end)

    Map.update!(
      data,
      :free_token_ids,
      &MapSet.union(&1, MapSet.new(free_token_ids))
    )
  end

  @spec fetch_edge_places(t()) :: t()
  defp fetch_edge_places(%__MODULE__{} = data) do
    %{
      application: application,
      case_schema: %Schema.Case{
        workflow_id: workflow_id
      }
    } = data

    {:ok, {start_place, end_place}} = WorkflowMetal.Storage.fetch_edge_places(application, workflow_id)

    %{data | start_place: start_place, end_place: end_place}
  end

  @spec update_case(t(), map()) :: t()
  defp update_case(%__MODULE__{} = data, params) do
    %{
      application: application,
      case_schema: case_schema
    } = data

    {:ok, case_schema} =
      WorkflowMetal.Storage.update_case(
        application,
        case_schema.id,
        params
      )

    new_data = %{data | case_schema: case_schema, state: case_schema.state}

    log_state_change(new_data, data.state)

    new_data
  end

  defp log_state_change(data, old_state) do
    case {old_state, data.state} do
      {:created, :active} ->
        Logger.debug(fn -> "#{describe(data)} is activated." end)

      {:active, :finished} ->
        Logger.debug(fn -> "#{describe(data)} is finished." end)

      {from, :terminated} ->
        Logger.debug(fn -> "#{describe(data)} is terminated from #{from}." end)

      _other ->
        :ok
    end
  end

  @spec do_activate_case(t()) :: t()
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

    genesis_token_schema =
      struct(
        Schema.Token,
        %{
          state: :free,
          workflow_id: workflow_id,
          place_id: start_place_id,
          case_id: case_id,
          produced_by_task_id: :genesis
        }
      )

    {:ok, token_schema} = do_issue_token(genesis_token_schema, data)

    %{data | free_token_ids: MapSet.put(free_token_ids, token_schema.id)}
  end

  defp do_issue_token(token_schema, %__MODULE__{} = data) do
    %{
      application: application
    } = data

    {:ok, token_schema} = WorkflowMetal.Storage.issue_token(application, token_schema)

    {:ok, _data} = upsert_ets_token(token_schema, data)

    {:ok, token_schema}
  end

  @spec do_issue_tokens([token_schema()], t()) :: {[token_schema()], t()}
  defp do_issue_tokens(token_schema_list, %__MODULE__{} = data) do
    new_tokens =
      Enum.map(token_schema_list, fn token_schema ->
        {:ok, token_schema} = do_issue_token(token_schema, data)

        token_schema
      end)

    {
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

  @spec do_offer_tokens(t()) :: t()
  defp do_offer_tokens(%__MODULE__{} = data) do
    %{
      token_table: token_table
    } = data

    token_table
    |> :ets.select([{{:_, :"$1", :free, :_, :_, :_}, [], [:"$1"]}])
    |> Enum.each(fn token_schema ->
      do_offer_token(token_schema, data)
    end)

    data
  end

  @spec do_offer_tokens([token_schema()], t()) :: t()
  defp do_offer_tokens(tokens, %__MODULE__{} = data) do
    Enum.each(tokens, fn token_schema -> do_offer_token(token_schema, data) end)
    data
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
      fetch_or_insert_task(transition, data)
    end)
    |> Stream.each(fn {:ok, task} ->
      :ok = WorkflowMetal.Task.Supervisor.offer_tokens(application, task.id, [token_schema])

      Logger.debug(fn ->
        "#{describe(data)}: offers a token(#{token_schema.id}) to the task(#{task.id})"
      end)
    end)
    |> Stream.run()
  end

  defp fetch_or_insert_task(transition, %__MODULE__{} = data) do
    %{id: transition_id} = transition

    case fetch_available_tasks(transition_id, data) do
      {:ok, [task]} ->
        {:ok, task}

      {:ok, []} ->
        %{
          application: application,
          case_schema: %Schema.Case{
            id: case_id,
            workflow_id: workflow_id
          }
        } = data

        task_schema = %Schema.Task{
          state: :started,
          case_id: case_id,
          transition_id: transition_id,
          workflow_id: workflow_id
        }

        {:ok, _} = WorkflowMetal.Storage.insert_task(application, task_schema)
    end
  end

  @spec do_lock_tokens(MapSet.t(token_id()), task_id(), t()) ::
          {:ok, [token_schema()], t()} | {:error, :tokens_not_available}
  defp do_lock_tokens(token_ids, task_id, %__MODULE__{} = data) do
    %{
      application: application,
      free_token_ids: free_token_ids
    } = data

    if MapSet.subset?(token_ids, free_token_ids) do
      {:ok, locked_token_schemas} =
        WorkflowMetal.Storage.lock_tokens(
          application,
          MapSet.to_list(token_ids),
          task_id
        )

      {:ok, data} =
        Enum.reduce(
          locked_token_schemas,
          {:ok, data},
          fn token_schema, {:ok, data} ->
            upsert_ets_token(token_schema, data)
          end
        )

      free_token_ids = MapSet.difference(free_token_ids, token_ids)

      {:ok, locked_token_schemas, %{data | free_token_ids: free_token_ids}}
    else
      {:error, :tokens_not_available}
    end
  end

  @spec do_consume_tokens(task_id(), t()) :: {[token_schema()], t()}
  defp do_consume_tokens(task_id, %__MODULE__{} = data) do
    %{
      application: application
    } = data

    token_ids = find_locked_token_ids(task_id, data)

    {:ok, tokens} = WorkflowMetal.Storage.consume_tokens(application, token_ids, task_id)

    {:ok, data} =
      Enum.reduce(tokens, {:ok, data}, fn token, {:ok, data} ->
        upsert_ets_token(token, data)
      end)

    {tokens, data}
  end

  @spec case_finishment(t()) :: {:finished, t()} | {:active, t()}
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
      match_spec = [{{free_token_id, :"$1", :free, :_, :_, :_}, [], [:"$1"]}],
      [%Schema.Token{place_id: ^end_place_id}] <- :ets.select(token_table, match_spec)
    ) do
      {:finished, data}
    else
      _ ->
        {:active, data}
    end
  end

  @spec do_finish_case(t()) :: t()
  defp do_finish_case(%__MODULE__{} = data) do
    %{
      application: application,
      free_token_ids: free_token_ids
    } = data

    [free_token_id] = MapSet.to_list(free_token_ids)

    {:ok, [termination_token]} =
      WorkflowMetal.Storage.consume_tokens(
        application,
        [free_token_id],
        :termination
      )

    {:ok, data} = upsert_ets_token(termination_token, data)

    data
  end

  @spec do_revoke_tokens([token_schema()], task_id(), t()) :: t()
  defp do_revoke_tokens(locked_token_schemas, except_task_id, %__MODULE__{} = data) do
    Enum.each(locked_token_schemas, fn locked_token ->
      :ok = do_revoke_token(locked_token, except_task_id, data)
    end)

    data
  end

  defp do_revoke_token(%Schema.Token{} = token_schema, except_task_id, %__MODULE__{} = data) do
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
      fetch_available_tasks(transition.id, data)
    end)
    |> Stream.each(fn
      {:ok, [%Schema.Task{id: task_id}]} when task_id !== except_task_id ->
        Logger.info(fn ->
          """
          #{describe(data)} withdraw token(#{inspect(token_schema.id)}) from task #{inspect(task_id)}.
          """
        end)

        :ok =
          WorkflowMetal.Task.Supervisor.withdraw_tokens(
            application,
            task_id,
            [token_schema]
          )

      {:ok, _tasks} ->
        # skip the non-running task server
        :skip
    end)
    |> Stream.run()

    :ok
  end

  defp fetch_available_tasks(transition_id, %__MODULE__{} = data) do
    %{
      application: application,
      case_schema: %Schema.Case{
        id: case_id
      }
    } = data

    WorkflowMetal.Storage.fetch_tasks(
      application,
      case_id,
      state: [:started, :allocated, :executing],
      transition_id: transition_id
    )
  end

  defp find_locked_token_ids(task_id, %__MODULE__{} = data) do
    %{
      token_table: token_table
    } = data

    :ets.select(token_table, [{{:"$1", :_, :locked, :_, task_id, :_}, [], [:"$1"]}])
  end

  @spec do_offer_tokens_to_task(task_id(), t()) :: {[token_schema()], t()}
  defp do_offer_tokens_to_task(task_id, %__MODULE__{} = data) do
    %{
      application: application,
      token_table: token_table
    } = data

    {
      :ok,
      %Schema.Task{
        transition_id: transition_id
      }
    } = WorkflowMetal.Storage.fetch_task(application, task_id)

    {:ok, arcs} =
      WorkflowMetal.Storage.fetch_arcs(
        application,
        {:transition, transition_id},
        :in
      )

    arcs
    |> Enum.map(& &1.place_id)
    |> case do
      [] ->
        {[], data}

      [_ | _] = place_ids ->
        tokens =
          :ets.select(token_table, [
            {{:_, :"$1", :"$2", :"$3", :"$4", :_},
             [
               ETSUtil.make_or([
                 ETSUtil.make_and([
                   ETSUtil.make_condition(:locked, :"$2", :"=:="),
                   ETSUtil.make_condition(task_id, :"$4", :"=:=")
                 ]),
                 ETSUtil.make_and([
                   ETSUtil.make_condition(:free, :"$2", :"=:="),
                   ETSUtil.make_condition(place_ids, :"$3", :in)
                 ])
               ])
             ], [:"$1"]}
          ])

        {tokens, data}
    end
  end

  @spec do_fetch_locked_tokens_from_task(task_id(), t()) :: [token_schema()]
  defp do_fetch_locked_tokens_from_task(task_id, %__MODULE__{} = data) do
    %{
      application: application
    } = data

    token_ids = find_locked_token_ids(task_id, data)

    {:ok, tokens} =
      WorkflowMetal.Storage.fetch_tokens(
        application,
        token_ids
      )

    tokens
  end

  @spec force_abandon_tasks(t()) :: t()
  defp force_abandon_tasks(%__MODULE__{} = data) do
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
        state: [:started, :allocated, :executing]
      )

    Enum.each(tasks, fn task ->
      WorkflowMetal.Task.Supervisor.force_abandon_task(application, task.id)
    end)

    data
  end

  defp upsert_ets_token(%Schema.Token{} = token_schema, %__MODULE__{} = data) do
    %{
      token_table: token_table
    } = data

    true =
      :ets.insert(
        token_table,
        {
          token_schema.id,
          token_schema,
          token_schema.state,
          token_schema.place_id,
          token_schema.locked_by_task_id,
          token_schema.consumed_by_task_id
        }
      )

    {:ok, data}
  end

  defp describe(%__MODULE__{} = data) do
    %{
      case_schema: %Schema.Case{
        id: case_id,
        workflow_id: workflow_id
      }
    } = data

    "[#{inspect(__MODULE__)}] Case<#{case_id}##{workflow_id}>"
  end
end
