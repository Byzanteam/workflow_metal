defmodule WorkflowMetal.Task.Task do
  @moduledoc """
  A `GenServer` to lock tokens and generate `workitem`.

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

  use GenServer, restart: :transient
  use TypedStruct

  alias WorkflowMetal.Controller.Join, as: JoinController
  alias WorkflowMetal.Controller.Split, as: SplitController
  alias WorkflowMetal.Storage.Schema

  require Logger

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
    field :state, WorkflowMetal.Storage.Schema.Task.state()
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

  @doc false
  @spec start_link(workflow_identifier, options) :: :gen_statem.start_ret()
  def start_link(workflow_identifier, options) do
    name = Keyword.fetch!(options, :name)
    task_schema = Keyword.fetch!(options, :task_schema)

    GenServer.start_link(
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
    GenServer.cast(task_server, :force_abandon)
  end

  @doc """
  Receive tokens from the case.
  """
  @spec receive_tokens(:gen_statem.server_ref(), [token_schema]) :: :ok
  def receive_tokens(task_server, token_schemas) do
    GenServer.cast(task_server, {:receive_tokens, token_schemas})
  end

  @doc """
  Discard tokens when the case withdraw them.

  eg: these tokens has been locked by the other token.
  """
  @spec discard_tokens(:gen_statem.server_ref(), [token_schema]) :: :ok
  def discard_tokens(task_server, token_schemas) do
    GenServer.cast(task_server, {:discard_tokens, token_schemas})
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
    GenServer.call(task_server, :preexecute)
  end

  @doc """
  Update the state of a workitem in the workitem_table.
  """
  @spec update_workitem(:gen_statem.server_ref(), workitem_id, workitem_state) :: :ok
  def update_workitem(task_server, workitem_id, workitem_state) do
    GenServer.cast(task_server, {:update_workitem, workitem_id, workitem_state})
  end

  # callbacks

  @impl GenServer
  def init({{application, _workflow_id}, task_schema}) do
    case task_schema.state do
      state when state in [:abandoned, :completed] ->
        {:stop, :task_not_available}

      state ->
        {
          :ok,
          %__MODULE__{
            application: application,
            task_schema: task_schema,
            state: state,
            token_table: :ets.new(:token_table, [:set, :private]),
            workitem_table: :ets.new(:workitem_table, [:set, :private])
          },
          {:continue, :after_start}
        }
    end
  end

  @impl GenServer
  def handle_continue(:after_start, %{state: state} = data) when state in [:started, :allocated] do
    data =
      data
      |> fetch_workitems()
      |> fetch_transition()
      |> request_tokens()
      |> start_created_workitems()

    {:noreply, data, get_timeout(data.application)}
  end

  def handle_continue(:after_start, %{state: :executing} = data) do
    data =
      data
      |> fetch_workitems()
      |> fetch_transition()
      |> fetch_locked_tokens()
      |> start_created_workitems()

    {:noreply, data, {:continue, :try_complete}}
  end

  @impl GenServer
  def handle_continue(:try_allocate, %{state: :started} = data) do
    case JoinController.task_enablement(data) do
      :ok ->
        data =
          data
          |> allocate_workitem()
          |> update_task(%{state: :allocated})

        {:noreply, data, get_timeout(data.application)}

      _other ->
        {:noreply, data, get_timeout(data.application)}
    end
  end

  @impl GenServer
  def handle_continue(:try_abandon_by_tokens, %{state: state} = data) when state in [:started, :allocated, :executing] do
    case tokens_abandonment(data) do
      {:ok, data} ->
        data =
          data
          |> do_abandon_workitems()
          |> update_task(%{state: :abandoned})

        {:noreply, data, {:continue, :stop_server}}

      _error ->
        {:noreply, data, get_timeout(data.application)}
    end
  end

  @impl GenServer
  def handle_continue(:try_complete, %{state: :executing} = data) do
    case task_completion(data) do
      :ok ->
        {_tokens, data} = do_consume_tokens(data)
        data = do_complete_task(data)

        {:noreply, data, {:continue, :stop_server}}

      _error ->
        {:noreply, data, get_timeout(data.application)}
    end
  end

  @impl GenServer
  def handle_continue(:try_abandon_by_workitems, %{state: state} = data) when state in [:allocated, :executing] do
    case workitems_abandonment(data) do
      {:ok, data} ->
        data =
          data
          |> unlock_tokens()
          |> do_abandon_workitems()
          |> update_task(%{state: :abandoned})

        {:noreply, data, {:continue, :stop_server}}

      _ ->
        {:noreply, data, get_timeout(data.application)}
    end
  end

  @impl GenServer
  def handle_continue(:stop_server, data) do
    {:stop, :normal, data}
  end

  @impl GenServer
  def handle_cast({:receive_tokens, token_schemas}, %{state: :started} = data) do
    data = Enum.reduce(token_schemas, data, &upsert_ets_token/2)

    {
      :noreply,
      data,
      {:continue, :try_allocate}
    }
  end

  @impl GenServer
  def handle_cast({:receive_tokens, token_schemas}, %{state: :allocated} = data) do
    data = Enum.reduce(token_schemas, data, &upsert_ets_token/2)

    {:noreply, data, get_timeout(data.application)}
  end

  @impl GenServer
  def handle_cast({:discard_tokens, token_schemas}, %{state: state} = data)
      when state in [:started, :allocated, :executing] do
    data = Enum.reduce(token_schemas, data, &remove_ets_token/2)

    {
      :noreply,
      data,
      {:continue, :try_abandon_by_tokens}
    }
  end

  @impl GenServer
  def handle_cast(:force_abandon, %{state: state} = data) when state in [:started, :allocated, :executing] do
    data =
      data
      |> do_abandon_workitems()
      |> update_task(%{state: :abandoned})

    {:noreply, data, {:continue, :stop_server}}
  end

  @impl GenServer
  def handle_cast({:update_workitem, workitem_id, :started}, %{state: state} = data)
      when state in [:allocated, :executing] do
    data = upsert_ets_workitem({workitem_id, :started}, data)

    {:noreply, data, get_timeout(data.application)}
  end

  @impl GenServer
  def handle_cast({:update_workitem, workitem_id, :completed}, %{state: :executing} = data) do
    data = upsert_ets_workitem({workitem_id, :completed}, data)

    {:noreply, data, {:continue, :try_complete}}
  end

  @impl GenServer
  def handle_cast({:update_workitem, workitem_id, :abandoned}, %{state: state} = data)
      when state not in [:abandoned, :completed] do
    data = upsert_ets_workitem({workitem_id, :abandoned}, data)

    {:noreply, data, {:continue, :try_abandon_by_workitems}}
  end

  @impl GenServer
  def handle_cast(_msg, %{} = data) do
    {:noreply, data, get_timeout(data.application)}
  end

  @impl GenServer
  def handle_call(:preexecute, _from, %__MODULE__{state: :allocated} = data) do
    case do_lock_tokens(data) do
      {:ok, locked_token_schemas, data} ->
        data = update_task(data, %{state: :executing})

        {:reply, {:ok, locked_token_schemas}, data}

      error ->
        {:reply, error, data, get_timeout(data.application)}
    end
  end

  @impl GenServer
  def handle_call(:preexecute, _from, %{state: :executing} = data) do
    %{
      token_table: token_table
    } = data

    tokens =
      token_table
      |> :ets.tab2list()
      |> Enum.reduce([], fn
        {_token_id, token_schema, :locked}, {:ok, tokens} ->
          [token_schema | tokens]

        _, acc ->
          acc
      end)

    {:reply, {:ok, tokens}, data, get_timeout(data.application)}
  end

  @impl GenServer
  def handle_call(_msg, _from, %{} = data) do
    {:reply, {:error, :task_not_available}, data, get_timeout(data.application)}
  end

  @impl GenServer
  def handle_info(:timeout, %__MODULE__{} = data) do
    Logger.debug(describe(data) <> " stopping due to inactivity timeout")

    {:stop, :normal, data}
  end

  @spec fetch_workitems(t()) :: t()
  defp fetch_workitems(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id
      }
    } = data

    {:ok, workitems} = WorkflowMetal.Storage.fetch_workitems(application, task_id)

    data = Enum.reduce(workitems, data, &upsert_ets_workitem/2)

    data
  end

  @spec fetch_transition(t()) :: t()
  defp fetch_transition(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        transition_id: transition_id
      }
    } = data

    {:ok, transition_schema} = WorkflowMetal.Storage.fetch_transition(application, transition_id)

    %{data | transition_schema: transition_schema}
  end

  @spec request_tokens(t()) :: t()
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
        data = Enum.reduce(tokens, data, &upsert_ets_token/2)

        data

      _ ->
        data
    end
  end

  @spec fetch_locked_tokens(t()) :: t()
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

    data = Enum.reduce(locked_token_schemas, data, &upsert_ets_token/2)

    data
  end

  @spec start_created_workitems(t()) :: t()
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

    data
  end

  @spec update_task(t(), map()) :: t()
  defp update_task(%__MODULE__{} = data, params) do
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

    new_data = %{data | task_schema: task_schema, state: task_schema.state}

    log_state_change(new_data, data.state)

    new_data
  end

  defp log_state_change(data, old_state) do
    case {old_state, data.state} do
      {:started, :allocated} ->
        Logger.debug(fn -> "#{describe(data)} allocate a workitem." end)

      {:allocated, :executing} ->
        Logger.debug(fn -> "#{describe(data)} start executing." end)

      {:executing, :completed} ->
        Logger.debug(fn -> "#{describe(data)} complete the execution." end)

      {from, :abandoned} ->
        Logger.debug(fn -> "#{describe(data)} has been abandoned from #{from}." end)

      _other ->
        :ok
    end
  end

  @spec allocate_workitem(t()) :: t()
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

    data = upsert_ets_workitem(workitem_schema, data)

    {:ok, _} =
      WorkflowMetal.Workitem.Supervisor.open_workitem(
        application,
        workitem_schema.id
      )

    data
  end

  @spec do_lock_tokens(t()) :: {:ok, [token_schema()], t()} | {:error, atom()}
  defp do_lock_tokens(%__MODULE__{} = data) do
    with(
      {:ok, token_ids} <- JoinController.preexecute(data),
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
      data = Enum.reduce(locked_token_schemas, data, &upsert_ets_token/2)

      {:ok, locked_token_schemas, data}
    end
  end

  @spec task_completion(t()) :: :ok | {:error, :task_not_completed}
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

  @spec do_consume_tokens(t()) :: {consumed_tokens :: [token_schema()], t()}
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

    data = Enum.reduce(tokens, data, &upsert_ets_token/2)

    {tokens, data}
  end

  @spec do_complete_task(t()) :: t()
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

    update_task(data, %{state: :completed, token_payload: token_payload})
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

  @spec tokens_abandonment(t()) :: {:ok, t()} | {:error, :task_not_abandoned}
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

  @spec unlock_tokens(t()) :: t()
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

    data
  end

  @spec do_abandon_workitems(t()) :: t()
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
        _data = upsert_ets_workitem({workitem_id, :abandoned}, data)

      _ ->
        :skip
    end)

    data
  end

  @spec upsert_ets_token(token_schema(), t()) :: t()
  defp upsert_ets_token(%Schema.Token{} = token_schema, %__MODULE__{} = data) do
    %{token_table: token_table} = data

    true =
      :ets.insert(token_table, {
        token_schema.id,
        token_schema,
        token_schema.state
      })

    data
  end

  @spec remove_ets_token(token_schema(), t()) :: t()
  defp remove_ets_token(%Schema.Token{} = token_schema, %__MODULE__{} = data) do
    %{token_table: token_table} = data
    true = :ets.delete(token_table, token_schema.id)

    data
  end

  @spec upsert_ets_workitem(workitem_schema(), t()) :: t()
  defp upsert_ets_workitem(%Schema.Workitem{} = workitem, %__MODULE__{} = data) do
    upsert_ets_workitem({workitem.id, workitem.state}, data)
  end

  @spec upsert_ets_workitem({workitem_id, workitem_state}, t()) :: t()
  defp upsert_ets_workitem({workitem_id, workitem_state}, %__MODULE__{} = data) do
    %{workitem_table: workitem_table} = data
    true = :ets.insert(workitem_table, {workitem_id, workitem_state})

    data
  end

  defp get_timeout(application) do
    application
    |> WorkflowMetal.Application.Config.get(:task)
    |> Kernel.||([])
    |> Keyword.get(:lifespan_timeout, :timer.minutes(1))
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
