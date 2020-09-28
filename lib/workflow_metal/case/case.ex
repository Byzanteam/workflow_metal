defmodule WorkflowMetal.Case.Case do
  @moduledoc """
  `GenStateMachine` process to present a workflow case.

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

  alias WorkflowMetal.Utils.ETS, as: ETSUtil

  alias WorkflowMetal.Storage.Schema

  require Logger

  use GenStateMachine,
    callback_mode: [:handle_event_function, :state_enter],
    restart: :transient

  use TypedStruct

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
  terminate a case.
  """
  @spec terminate(:gen_statem.server_ref()) :: :ok
  def terminate(case_server) do
    GenStateMachine.cast(case_server, :terminate)
  end

  @doc """
  Issue tokens.
  """
  @spec issue_tokens(:gen_statem.server_ref(), nonempty_list(token_schema)) ::
          {:ok, nonempty_list(token_schema)}
  def issue_tokens(case_server, [_ | _] = token_schema_list) do
    GenStateMachine.call(case_server, {:issue_tokens, token_schema_list})
  end

  @doc """
  Lock tokens.
  """
  @spec lock_tokens(:gen_statem.server_ref(), [token_id], task_id) ::
          {:ok, nonempty_list(token_schema)}
          | {:error, :tokens_not_available}
  def lock_tokens(case_server, [_ | _] = token_ids, task_id) do
    GenStateMachine.call(case_server, {:lock_tokens, token_ids, task_id})
  end

  @doc """
  Consume tokens.
  """
  @spec consume_tokens(:gen_statem.server_ref(), task_id) ::
          {:ok, nonempty_list(token_schema)} | {:error, :tokens_not_available}
  def consume_tokens(case_server, task_id) do
    GenStateMachine.call(case_server, {:consume_tokens, task_id})
  end

  @doc """
  Offer `:free` and `:locked` tokens to the task.

  eg: request `:free` and `:locked` tokens when a task restore from storage.
  """
  @spec offer_tokens_to_task(:gen_statem.server_ref(), task_id) :: {:ok, [token_schema]}
  def offer_tokens_to_task(case_server, task_id) do
    GenStateMachine.call(case_server, {:offer_tokens_to_task, task_id})
  end

  @doc """
  Free tokens that locked by the task.

  eg: free `:locked` tokens when a task has been abandoned.
  """
  @spec free_tokens_from_task(:gen_statem.server_ref(), task_id) :: :ok
  def free_tokens_from_task(case_server, task_id) do
    GenStateMachine.call(case_server, {:free_tokens_from_task, task_id})
  end

  @doc """
  Free tokens that locked by the task.

  eg: free `:locked` tokens when a task has been abandoned.
  """
  @spec fetch_locked_tokens_from_task(:gen_statem.server_ref(), task_id) :: {:ok, [token_schema]}
  def fetch_locked_tokens_from_task(case_server, task_id) do
    GenStateMachine.call(case_server, {:fetch_locked_tokens_from_task, task_id})
  end

  # Server (callbacks)

  @impl true
  def init({{application, _workflow_id}, case_schema}) do
    %{
      state: state
    } = case_schema

    if state in [:terminated, :finished] do
      {:stop, :case_not_available}
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
  def handle_event(:enter, state, state, %__MODULE__{} = data) do
    {:ok, data} = fetch_edge_places(data)

    case state do
      :created ->
        {
          :keep_state,
          data,
          {:state_timeout, 1, :after_start}
        }

      :active ->
        {:ok, data} = fetch_unconsumed_tokens(data)

        {
          :keep_state,
          data,
          {:state_timeout, 1, :after_start}
        }

      :terminated ->
        :keep_state_and_data
    end
  end

  @impl GenStateMachine
  def handle_event(:enter, old_state, state, %__MODULE__{} = data) do
    case {old_state, state} do
      {:created, :active} ->
        Logger.debug(fn -> "#{describe(data)} is activated." end)

        {:keep_state, data}

      {:active, :finished} ->
        Logger.debug(fn -> "#{describe(data)} is finished." end)

        {:stop, :normal}

      {_, :terminated} ->
        {:ok, _data} = force_abandon_tasks(data)
        Logger.debug(fn -> "#{describe(data)} is terminated." end)

        {:stop, :normal}
    end
  end

  @impl GenStateMachine
  def handle_event(:state_timeout, :after_start, state, %__MODULE__{} = data) do
    case state do
      :created ->
        {:ok, data} = do_activate_case(data)
        {:ok, data} = update_case(%{state: :active}, data)

        {
          :next_state,
          :active,
          data,
          {:next_event, :internal, :offer_tokens}
        }

      :active ->
        {
          :keep_state_and_data,
          {:next_event, :internal, :offer_tokens}
        }
    end
  end

  @impl GenStateMachine
  def handle_event(:internal, :offer_tokens, :active, %__MODULE__{} = data) do
    {:ok, data} = do_offer_tokens(data)

    {
      :keep_state,
      data,
      {:next_event, :internal, :try_finish}
    }
  end

  @impl GenStateMachine
  def handle_event(:internal, {:offer_tokens, tokens}, :active, %__MODULE__{} = data) do
    {:ok, data} = do_offer_tokens(tokens, data)

    {
      :keep_state,
      data,
      {:next_event, :internal, :try_finish}
    }
  end

  @impl GenStateMachine
  def handle_event(
        :internal,
        {:revoke_tokens, locked_token_schemas, except_task_id},
        :active,
        %__MODULE__{} = data
      ) do
    {:ok, data} = do_revoke_tokens(locked_token_schemas, except_task_id, data)

    {:keep_state, data}
  end

  @impl GenStateMachine
  def handle_event(:internal, :try_finish, :active, %__MODULE__{} = data) do
    with(
      {:finished, data} <- case_finishment(data),
      {:ok, data} <- do_finish_case(data)
    ) do
      {:ok, data} = update_case(%{state: :finished}, data)

      {
        :next_state,
        :finished,
        data
      }
    else
      _ ->
        :keep_state_and_data
    end
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
          {:reply, from, {:ok, locked_token_schemas}}
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
        {:consume_tokens, task_id},
        :active,
        %__MODULE__{} = data
      ) do
    case do_consume_tokens(task_id, data) do
      {:ok, tokens, data} ->
        Logger.debug(fn ->
          "#{describe(data)}: tokens(#{tokens |> Enum.map_join(", ", & &1.id)}) have been consumed by the task(#{
            task_id
          })"
        end)

        {
          :keep_state,
          data,
          [
            {:reply, from, {:ok, tokens}},
            {:next_event, :internal, {:revoke_tokens, tokens, task_id}}
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
        {:issue_tokens, token_schema_list},
        :active,
        %__MODULE__{} = data
      ) do
    {:ok, tokens, data} = do_issue_tokens(token_schema_list, data)

    Logger.debug(fn ->
      "#{describe(data)}: tokens(#{tokens |> Enum.map_join(", ", & &1.id)}) have been issued"
    end)

    {
      :keep_state,
      data,
      [
        {:reply, from, {:ok, tokens}},
        {:next_event, :internal, {:offer_tokens, tokens}}
      ]
    }
  end

  @impl GenStateMachine
  def handle_event({:call, from}, {:offer_tokens_to_task, task_id}, :active, %__MODULE__{} = data) do
    {:ok, tokens, data} = do_offer_tokens_to_task(task_id, data)

    {:keep_state, data, {:reply, from, {:ok, tokens}}}
  end

  @impl GenStateMachine
  def handle_event(
        {:call, from},
        {:fetch_locked_tokens_from_task, task_id},
        :active,
        %__MODULE__{} = data
      ) do
    {:ok, tokens} = do_fetch_locked_tokens_from_task(task_id, data)

    {:keep_state_and_data, {:reply, from, {:ok, tokens}}}
  end

  @impl GenStateMachine
  def handle_event({:call, from}, _event_content, _state, %__MODULE__{}) do
    {:keep_state_and_data, {:reply, from, {:error, :case_not_available}}}
  end

  @impl GenStateMachine
  def handle_event(
        :cast,
        {:free_tokens_from_task, task_id},
        :active,
        %__MODULE__{} = data
      ) do
    token_ids = find_locked_token_ids(task_id, data)

    {:ok, tokens} = WorkflowMetal.Storage.unlock_tokens(data.application, token_ids)

    Logger.debug(fn ->
      "#{describe(data)}: tokens(#{tokens |> Enum.map(& &1.id) |> Enum.join(", ")}) have been freed by the task(#{
        task_id
      })"
    end)

    {
      :keep_state,
      data,
      {:next_event, :internal, {:offer_tokens, tokens}}
    }
  end

  @impl GenStateMachine
  def handle_event(:cast, :terminate, state, %__MODULE__{} = data)
      when state in [:created, :active] do
    {:ok, data} = update_case(%{state: :terminated}, data)

    {:next_state, :terminated, data}
  end

  @impl GenStateMachine
  def format_status(_reason, [_pdict, state, data]) do
    {:state, %{current_state: state, data: data}}
  end

  defp fetch_unconsumed_tokens(%__MODULE__{} = data) do
    %{
      application: application,
      case_schema: %Schema.Case{
        id: case_id
      }
    } = data

    with({:ok, tokens} <- WorkflowMetal.Storage.fetch_unconsumed_tokens(application, case_id)) do
      free_token_ids =
        Enum.reduce(tokens, MapSet.new(), fn
          %Schema.Token{state: :free} = token, acc ->
            {:ok, _data} = upsert_ets_token(token, data)
            MapSet.put(acc, token.id)

          %Schema.Token{state: :locked} = token, acc ->
            {:ok, _data} = upsert_ets_token(token, data)
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

  defp update_case(params, %__MODULE__{} = data) do
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

    genesis_token_schema =
      struct(
        Schema.Token,
        %{
          id: nil,
          state: :free,
          workflow_id: workflow_id,
          place_id: start_place_id,
          case_id: case_id,
          produced_by_task_id: :genesis
        }
      )

    {:ok, token_schema} = do_issue_token(genesis_token_schema, data)

    {
      :ok,
      %{data | free_token_ids: MapSet.put(free_token_ids, token_schema.id)}
    }
  end

  defp do_issue_token(token_schema, %__MODULE__{} = data) do
    %{
      application: application
    } = data

    {:ok, token_schema} = WorkflowMetal.Storage.issue_token(application, token_schema)

    {:ok, _data} = upsert_ets_token(token_schema, data)

    {:ok, token_schema}
  end

  defp do_issue_tokens(token_schema_list, %__MODULE__{} = data) do
    new_tokens =
      Enum.map(token_schema_list, fn token_schema ->
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
    |> :ets.select([{{:_, :"$1", :free, :_, :_, :_}, [], [:"$1"]}])
    |> Enum.each(fn token_schema ->
      do_offer_token(token_schema, data)
    end)

    {:ok, data}
  end

  defp do_offer_tokens(tokens, %__MODULE__{} = data) do
    tokens
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
          id: nil,
          state: :started,
          workflow_id: workflow_id,
          case_id: case_id,
          transition_id: transition_id
        }

        {:ok, _} = WorkflowMetal.Storage.insert_task(application, task_schema)
    end
  end

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

  defp do_consume_tokens(task_id, %__MODULE__{} = data) do
    %{
      application: application
    } = data

    token_ids = find_locked_token_ids(task_id, data)

    with(
      {:ok, tokens} <- WorkflowMetal.Storage.consume_tokens(application, token_ids, task_id)
    ) do
      {:ok, data} =
        Enum.reduce(tokens, {:ok, data}, fn token, {:ok, data} ->
          upsert_ets_token(token, data)
        end)

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
      match_spec = [{{free_token_id, :"$1", :free, :_, :_, :_}, [], [:"$1"]}],
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

    {:ok, data}
  end

  defp do_revoke_tokens(locked_token_schemas, except_task_id, %__MODULE__{} = data) do
    Enum.each(locked_token_schemas, fn locked_token ->
      :ok = do_revoke_token(locked_token, except_task_id, data)
    end)

    {:ok, data}
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
          #{describe(data)} withdraw token(#{inspect(token_schema.id)}) from task #{
            inspect(task_id)
          }.
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

    token_table
    |> :ets.select([
      {
        {:"$1", :_, :locked, :_, task_id, :_},
        [],
        [:"$1"]
      }
    ])
  end

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
        {:ok, [], data}

      [_ | _] = place_ids ->
        tokens =
          token_table
          |> :ets.select([
            {
              {:_, :"$1", :"$2", :"$3", :"$4", :_},
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
              ],
              [:"$1"]
            }
          ])

        {:ok, tokens, data}
    end
  end

  defp do_fetch_locked_tokens_from_task(task_id, %__MODULE__{} = data) do
    %{
      application: application
    } = data

    token_ids = find_locked_token_ids(task_id, data)

    WorkflowMetal.Storage.fetch_tokens(
      application,
      token_ids
    )
  end

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

    tasks
    |> Enum.each(fn task ->
      WorkflowMetal.Task.Supervisor.force_abandon_task(application, task.id)
    end)

    {:ok, data}
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
