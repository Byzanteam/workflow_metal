defmodule WorkflowMetal.Task.Task do
  @moduledoc """
  A `GenStateMachine` to lock tokens and generate `workitem`.

  ## Storage
  The data of `:token_table` is stored in ETS in the following format:
      {token_id, token_schema, token_state}

  The data of `:workitem_table` is stored in ETS in the following format:
      {workitem_id, workitem_state}

  ## State

  ```
  started+-------->allocated+------->executing+------->completed
      +                +                 +
      |                |                 |
      |                v                 |
      +----------->abandoned<------------+
  ```

  ## Restore

  Restore a task while restoring its non-ending(`created` and `started`) workitems.
  """

  require Logger

  use GenStateMachine,
    callback_mode: [:handle_event_function, :state_enter],
    restart: :transient

  use TypedStruct

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Supervisor.workflow_identifier()

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type transition_schema :: WorkflowMetal.Storage.Schema.Transition.t()

  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()
  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()
  @type task_schema :: WorkflowMetal.Storage.Schema.Task.t()

  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()
  @type workitem_state :: WorkflowMetal.Storage.Schema.Workitem.state()
  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()

  typedstruct do
    field :application, application()
    field :task_schema, task_schema()
    field :transition_schema, transition_schema()
    field :token_table, :ets.tid()
    field :workitem_table, :ets.tid()
  end

  @type options :: [
          name: term(),
          task_schema: task_schema()
        ]

  @type on_preexecute ::
          {:ok, nonempty_list(token_schema)}
          | {:error, :tokens_not_available}
          | {:error, :task_not_enabled}

  alias WorkflowMetal.Controller.Join, as: JoinController
  alias WorkflowMetal.Controller.Split, as: SplitController
  alias WorkflowMetal.Storage.Schema

  @doc false
  @spec start_link(workflow_identifier, options) :: :gen_statem.start_ret()
  def start_link(workflow_identifier, options) do
    name = Keyword.fetch!(options, :name)
    task_schema = Keyword.fetch!(options, :task_schema)

    GenStateMachine.start_link(
      __MODULE__,
      {workflow_identifier, task_schema},
      name: name
    )
  end

  @doc false
  @spec name({workflow_id, case_id, transition_id, task_id}) :: term()
  def name({workflow_id, transition_id, case_id, task_id}) do
    {__MODULE__, {workflow_id, transition_id, case_id, task_id}}
  end

  @doc false
  @spec name(task_schema) :: term()
  def name(%Schema.Task{} = task_schema) do
    %{
      id: task_id,
      workflow_id: workflow_id,
      transition_id: transition_id,
      case_id: case_id
    } = task_schema

    name({workflow_id, transition_id, case_id, task_id})
  end

  @doc false
  @spec via_name(application, {workflow_id, transition_id, case_id, task_id}) :: term()
  def via_name(application, {workflow_id, transition_id, case_id, task_id}) do
    WorkflowMetal.Registration.via_tuple(
      application,
      name({workflow_id, transition_id, case_id, task_id})
    )
  end

  @doc false
  @spec via_name(application, task_schema) :: term()
  def via_name(application, %Schema.Task{} = task_schema) do
    WorkflowMetal.Registration.via_tuple(application, name(task_schema))
  end

  @doc """
  Abandon the task forcibly.
  """
  @spec force_abandon(:gen_statem.server_ref()) :: :ok
  def force_abandon(task_server) do
    GenStateMachine.cast(task_server, :force_abandon)
  end

  @doc """
  Receive tokens from the case.
  """
  @spec receive_tokens(:gen_statem.server_ref(), [token_schema]) :: :ok
  def receive_tokens(task_server, token_schemas) do
    GenStateMachine.cast(task_server, {:receive_tokens, token_schemas})
  end

  @doc """
  Discard tokens when the case withdraw them.

  eg: these tokens has been locked by the other token.
  """
  @spec discard_tokens(:gen_statem.server_ref(), [token_schema]) :: :ok
  def discard_tokens(task_server, token_schemas) do
    GenStateMachine.cast(task_server, {:discard_tokens, token_schemas})
  end

  @doc """
  Pre-execute the given task, return with locked tokens.

  ### Lock tokens

  If tokens are already locked by the task, return `:ok` too.

  When the task is not enabled, return `{:error, :task_not_enabled}`.
  When fail to lock tokens, return `{:error, :tokens_not_available}`.
  """
  @spec preexecute(:gen_statem.server_ref()) :: on_preexecute
  def preexecute(task_server) do
    GenStateMachine.call(task_server, :preexecute)
  end

  @doc """
  Update the state of a workitem in the workitem_table.
  """
  @spec update_workitem(:gen_statem.server_ref(), workitem_id, workitem_state) :: :ok
  def update_workitem(task_server, workitem_id, workitem_state) do
    GenStateMachine.cast(task_server, {:update_workitem, workitem_id, workitem_state})
  end

  # callbacks

  @impl GenStateMachine
  def init({{application, _workflow_id}, task_schema}) do
    %{
      state: state
    } = task_schema

    if state in [:abandoned, :completed] do
      {:stop, :task_not_available}
    else
      {
        :ok,
        state,
        %__MODULE__{
          application: application,
          task_schema: task_schema,
          token_table: :ets.new(:token_table, [:set, :private]),
          workitem_table: :ets.new(:workitem_table, [:set, :private])
        }
      }
    end
  end

  @impl GenStateMachine
  # init
  def handle_event(:enter, state, state, %__MODULE__{} = data) do
    {:ok, data} = fetch_workitems(data)
    {:ok, data} = fetch_transition(data)

    case state do
      :started ->
        {:ok, data} = request_tokens(data)

        {
          :keep_state,
          data,
          {:state_timeout, 1, :after_start}
        }

      :allocated ->
        {:ok, data} = request_tokens(data)

        {
          :keep_state,
          data,
          {:state_timeout, 1, :after_start}
        }

      :executing ->
        {:ok, data} = fetch_locked_tokens(data)

        {
          :keep_state,
          data,
          {:state_timeout, 1, :after_start}
        }
    end
  end

  @impl GenStateMachine
  def handle_event(:enter, old_state, state, %__MODULE__{} = data) do
    case {old_state, state} do
      {:started, :allocated} ->
        Logger.debug(fn -> "#{describe(data)} allocate a workitem." end)

        {:keep_state, data}

      {:allocated, :executing} ->
        Logger.debug(fn -> "#{describe(data)} start executing." end)

        {:keep_state, data}

      {:executing, :completed} ->
        Logger.debug(fn -> "#{describe(data)} complete the execution." end)

        {:stop, :normal}

      {from, :abandoned} when from in [:started, :allocated, :executing] ->
        Logger.debug(fn -> "#{describe(data)} has been abandoned." end)

        {:stop, :normal}
    end
  end

  @impl GenStateMachine
  def handle_event(:state_timeout, :after_start, state, %__MODULE__{} = data) do
    {:ok, data} = start_created_workitems(data)

    case state do
      :executing ->
        {
          :keep_state,
          data,
          {:next_event, :cast, :try_complete}
        }

      _ ->
        :keep_state_and_data
    end
  end

  @impl GenStateMachine
  def handle_event(:cast, {:receive_tokens, token_schemas}, :started, %__MODULE__{} = data) do
    {:ok, data} =
      Enum.reduce(token_schemas, {:ok, data}, fn token_schema, {:ok, data} ->
        upsert_ets_token(token_schema, data)
      end)

    {
      :keep_state,
      data,
      {:next_event, :cast, :try_allocate}
    }
  end

  @impl GenStateMachine
  def handle_event(:cast, {:receive_tokens, token_schemas}, :allocated, %__MODULE__{} = data) do
    {:ok, data} =
      Enum.reduce(token_schemas, {:ok, data}, fn token_schema, {:ok, data} ->
        upsert_ets_token(token_schema, data)
      end)

    {
      :keep_state,
      data
    }
  end

  @impl GenStateMachine
  def handle_event(:cast, {:discard_tokens, token_schemas}, state, %__MODULE__{} = data)
      when state in [:started, :allocated, :executing] do
    {:ok, data} =
      Enum.reduce(token_schemas, {:ok, data}, fn token_schema, {:ok, data} ->
        remove_ets_token(token_schema, data)
      end)

    {
      :keep_state,
      data,
      {:next_event, :cast, :try_abandon_by_tokens}
    }
  end

  @impl GenStateMachine
  def handle_event(:cast, :try_allocate, :started, %__MODULE__{} = data) do
    case JoinController.task_enablement(data) do
      {:ok, _token_ids} ->
        {:ok, data} = allocate_workitem(data)
        {:ok, data} = update_task(%{state: :allocated}, data)

        {
          :next_state,
          :allocated,
          data
        }

      _ ->
        :keep_state_and_data
    end
  end

  @impl GenStateMachine
  def handle_event(:cast, :try_complete, :executing, %__MODULE__{} = data) do
    with(
      :ok <- task_completion(data),
      {:ok, _tokens, data} <- do_consume_tokens(data),
      {:ok, data} <- do_complete_task(data)
    ) do
      {
        :next_state,
        :completed,
        data
      }
    else
      _ ->
        :keep_state_and_data
    end
  end

  @impl GenStateMachine
  def handle_event(:cast, :try_abandon_by_workitems, state, %__MODULE__{} = data)
      when state in [:allocated, :executing] do
    case workitems_abandonment(data) do
      {:ok, data} ->
        {:ok, data} = unlock_tokens(data)
        {:ok, data} = do_abandon_workitems(data)
        {:ok, data} = update_task(%{state: :abandoned}, data)

        {
          :next_state,
          :abandoned,
          data
        }

      _ ->
        :keep_state_and_data
    end
  end

  @impl GenStateMachine
  def handle_event(:cast, :try_abandon_by_tokens, state, %__MODULE__{} = data)
      when state in [:started, :allocated, :executing] do
    case tokens_abandonment(data) do
      {:ok, data} ->
        {:ok, data} = do_abandon_workitems(data)
        {:ok, data} = update_task(%{state: :abandoned}, data)

        {
          :next_state,
          :abandoned,
          data
        }

      _ ->
        :keep_state_and_data
    end
  end

  @impl GenStateMachine
  def handle_event(:cast, :force_abandon, state, %__MODULE__{} = data)
      when state in [:started, :allocated, :executing] do
    {:ok, data} = do_abandon_workitems(data)
    {:ok, data} = update_task(%{state: :abandoned}, data)

    {
      :next_state,
      :abandoned,
      data
    }
  end

  @impl GenStateMachine
  def handle_event(
        :cast,
        {:update_workitem, workitem_id, :started},
        state,
        %__MODULE__{} = data
      )
      when state in [:allocated, :executing] do
    {:ok, data} = upsert_ets_workitem({workitem_id, :started}, data)

    {:keep_state, data}
  end

  @impl GenStateMachine
  def handle_event(
        :cast,
        {:update_workitem, workitem_id, :completed},
        :executing,
        %__MODULE__{} = data
      ) do
    {:ok, data} = upsert_ets_workitem({workitem_id, :completed}, data)

    {:keep_state, data, {:next_event, :cast, :try_complete}}
  end

  @impl GenStateMachine
  def handle_event(
        :cast,
        {:update_workitem, workitem_id, :abandoned},
        state,
        %__MODULE__{} = data
      )
      when state not in [:abandoned, :completed] do
    {:ok, data} = upsert_ets_workitem({workitem_id, :abandoned}, data)

    {:keep_state, data, {:next_event, :cast, :try_abandon_by_workitems}}
  end

  @impl GenStateMachine
  def handle_event(:cast, _event_content, _state, %__MODULE__{}) do
    :keep_state_and_data
  end

  @impl GenStateMachine
  def handle_event({:call, from}, :preexecute, :allocated, %__MODULE__{} = data) do
    case do_lock_tokens(data) do
      {:ok, locked_token_schemas, data} ->
        {:ok, data} = update_task(%{state: :executing}, data)

        {
          :next_state,
          :executing,
          data,
          {:reply, from, {:ok, locked_token_schemas}}
        }

      error ->
        {
          :keep_state_and_data,
          {:reply, from, error}
        }
    end
  end

  @impl GenStateMachine
  def handle_event({:call, from}, :preexecute, :executing, %__MODULE__{} = data) do
    %{
      token_table: token_table
    } = data

    reply =
      token_table
      |> :ets.tab2list()
      |> Enum.reduce({:ok, []}, fn
        {_token_id, token_schema, :locked}, {:ok, tokens} ->
          {:ok, [token_schema | tokens]}

        _, acc ->
          acc
      end)

    {
      :keep_state,
      data,
      {:reply, from, reply}
    }
  end

  @impl GenStateMachine
  def handle_event({:call, from}, _event_content, _state, %__MODULE__{}) do
    {:keep_state_and_data, {:reply, from, {:error, :task_not_available}}}
  end

  @impl GenStateMachine
  def format_status(_reason, [_pdict, state, data]) do
    {:state, %{current_state: state, data: data}}
  end

  defp fetch_workitems(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id
      }
    } = data

    {:ok, workitems} = WorkflowMetal.Storage.fetch_workitems(application, task_id)

    {:ok, _data} =
      Enum.reduce(
        workitems,
        {:ok, data},
        fn workitem, {:ok, data} ->
          upsert_ets_workitem(workitem, data)
        end
      )
  end

  defp fetch_transition(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        transition_id: transition_id
      }
    } = data

    {:ok, transition_schema} = WorkflowMetal.Storage.fetch_transition(application, transition_id)

    {:ok, %{data | transition_schema: transition_schema}}
  end

  defp request_tokens(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id,
        case_id: case_id
      }
    } = data

    case WorkflowMetal.Case.Supervisor.request_tokens(
           application,
           case_id,
           task_id
         ) do
      {:ok, tokens} ->
        {:ok, data} =
          Enum.reduce(
            tokens,
            {:ok, data},
            fn token_schema, {:ok, data} ->
              upsert_ets_token(token_schema, data)
            end
          )

        {:ok, data}

      _ ->
        {:ok, data}
    end
  end

  defp fetch_locked_tokens(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id,
        case_id: case_id
      }
    } = data

    {:ok, locked_token_schemas} =
      WorkflowMetal.Case.Supervisor.fetch_locked_tokens(
        application,
        case_id,
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

    {:ok, data}
  end

  defp start_created_workitems(%__MODULE__{} = data) do
    %{
      application: application,
      workitem_table: workitem_table
    } = data

    workitem_table
    |> :ets.select([{{:"$1", :created}, [], [:"$1"]}])
    |> Enum.each(fn workitem_id ->
      {:ok, _} =
        WorkflowMetal.Workitem.Supervisor.open_workitem(
          application,
          workitem_id
        )
    end)

    {:ok, data}
  end

  defp update_task(params, %__MODULE__{} = data) do
    %{
      application: application,
      task_schema: task_schema
    } = data

    {:ok, task_schema} =
      WorkflowMetal.Storage.update_task(
        application,
        task_schema.id,
        params
      )

    {:ok, %{data | task_schema: task_schema}}
  end

  defp allocate_workitem(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id,
        workflow_id: workflow_id,
        transition_id: transition_id,
        case_id: case_id
      }
    } = data

    workitem_schema =
      struct(
        Schema.Workitem,
        %{
          state: :created,
          workflow_id: workflow_id,
          transition_id: transition_id,
          case_id: case_id,
          task_id: task_id
        }
      )

    {:ok, workitem_schema} = WorkflowMetal.Storage.insert_workitem(application, workitem_schema)

    {:ok, data} = upsert_ets_workitem(workitem_schema, data)

    {:ok, _} =
      WorkflowMetal.Workitem.Supervisor.open_workitem(
        application,
        workitem_schema.id
      )

    {:ok, data}
  end

  defp do_lock_tokens(%__MODULE__{} = data) do
    with(
      {:ok, token_ids} <- JoinController.task_enablement(data),
      %{
        application: application,
        task_schema: %Schema.Task{id: task_id, case_id: case_id}
      } = data,
      {:ok, locked_token_schemas} <-
        WorkflowMetal.Case.Supervisor.lock_tokens(
          application,
          case_id,
          token_ids,
          task_id
        )
    ) do
      {:ok, data} =
        Enum.reduce(
          locked_token_schemas,
          {:ok, data},
          fn token_schema, {:ok, data} ->
            upsert_ets_token(token_schema, data)
          end
        )

      {:ok, locked_token_schemas, data}
    else
      {:error, :tokens_not_available} ->
        # retry
        do_lock_tokens(data)

      error ->
        error
    end
  end

  defp task_completion(%__MODULE__{} = data) do
    data
    |> Map.fetch!(:workitem_table)
    |> :ets.tab2list()
    |> Enum.all?(fn
      {_workitem_id, :completed} -> true
      {_workitem_id, :abandoned} -> true
      _ -> false
    end)
    |> case do
      true -> :ok
      false -> {:error, :task_not_completed}
    end
  end

  defp do_consume_tokens(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id,
        case_id: case_id
      }
    } = data

    {:ok, tokens} =
      WorkflowMetal.Case.Supervisor.consume_tokens(
        application,
        case_id,
        task_id
      )

    {:ok, data} =
      Enum.reduce(tokens, {:ok, data}, fn token, {:ok, data} ->
        upsert_ets_token(token, data)
      end)

    {:ok, tokens, data}
  end

  defp do_complete_task(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        case_id: case_id
      }
    } = data

    {:ok, token_payload} = build_token_payload(data)

    {:ok, token_schema_list} = SplitController.issue_tokens(data, token_payload)

    {:ok, _tokens} =
      WorkflowMetal.Case.Supervisor.issue_tokens(
        application,
        case_id,
        token_schema_list
      )

    update_task(%{state: :completed, token_payload: token_payload}, data)
  end

  defp build_token_payload(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id
      },
      transition_schema: %Schema.Transition{
        executor: executor,
        executor_params: executor_params
      }
    } = data

    {:ok, workitems} =
      WorkflowMetal.Storage.fetch_workitems(
        application,
        task_id
      )

    executor.build_token_payload(
      workitems,
      executor_params: executor_params,
      application: application
    )
  end

  defp workitems_abandonment(%__MODULE__{} = data) do
    %{
      workitem_table: workitem_table
    } = data

    workitem_table
    |> :ets.tab2list()
    |> Enum.all?(fn {_workitem_id, workitem_state} ->
      workitem_state === :abandoned
    end)
    |> case do
      true -> {:ok, data}
      false -> {:error, :task_not_abandoned}
    end
  end

  defp tokens_abandonment(%__MODULE__{} = data) do
    %{
      token_table: token_table
    } = data

    token_table
    |> :ets.tab2list()
    |> case do
      [] -> {:ok, data}
      _ -> {:error, :task_not_abandoned}
    end
  end

  defp unlock_tokens(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id,
        case_id: case_id
      },
      token_table: token_table
    } = data

    case WorkflowMetal.Case.Supervisor.unlock_tokens(application, case_id, task_id) do
      :ok -> :ok
      {:error, :case_not_available} -> :ok
    end

    true = :ets.delete_all_objects(token_table)

    {:ok, data}
  end

  defp do_abandon_workitems(%__MODULE__{} = data) do
    %{
      application: application,
      workitem_table: workitem_table
    } = data

    workitem_table
    |> :ets.tab2list()
    |> Enum.each(fn
      {workitem_id, state} when state in [:created, :started] ->
        :ok = WorkflowMetal.Workitem.Supervisor.abandon_workitem(application, workitem_id)
        {:ok, _data} = upsert_ets_workitem({workitem_id, :abandoned}, data)

      _ ->
        :skip
    end)

    {:ok, data}
  end

  defp upsert_ets_token(%Schema.Token{} = token_schema, %__MODULE__{} = data) do
    %{token_table: token_table} = data

    true =
      :ets.insert(token_table, {
        token_schema.id,
        token_schema,
        token_schema.state
      })

    {:ok, data}
  end

  defp remove_ets_token(%Schema.Token{} = token_schema, %__MODULE__{} = data) do
    %{token_table: token_table} = data
    true = :ets.delete(token_table, token_schema.id)

    {:ok, data}
  end

  defp upsert_ets_workitem(%Schema.Workitem{} = workitem, %__MODULE__{} = data) do
    %{workitem_table: workitem_table} = data
    true = :ets.insert(workitem_table, {workitem.id, workitem.state})

    {:ok, data}
  end

  defp upsert_ets_workitem({workitem_id, workitem_state}, %__MODULE__{} = data) do
    %{workitem_table: workitem_table} = data
    true = :ets.insert(workitem_table, {workitem_id, workitem_state})

    {:ok, data}
  end

  defp describe(%__MODULE__{} = data) do
    %{
      task_schema: %Schema.Task{
        id: task_id,
        workflow_id: workflow_id,
        transition_id: transition_id,
        case_id: case_id
      }
    } = data

    "[#{inspect(__MODULE__)}] Task<#{task_id}@#{case_id}##{transition_id}.#{workflow_id}>"
  end
end
