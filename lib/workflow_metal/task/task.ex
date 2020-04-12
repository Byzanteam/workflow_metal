defmodule WorkflowMetal.Task.Task do
  @moduledoc """
  A `GenStateMachine` to lock tokens and generate `workitem`.

  ## Storage
  The data of `:token_table` is stored in ETS in the following format:
      {token_id :: token_id, place_id :: place_id, token_state :: token_state}

  The data of `:workitem_table` is stored in ETS in the following format:
      {workitem_id :: workitem_id, workitem_schema, workitem_state :: workitem_state}

  ## State

  ```
  started+-------->executing+------->completed
      +               +
      |               |
      |               v
      +---------->abandoned
  ```
  """

  require Logger

  use GenStateMachine,
    callback_mode: [:handle_event_function, :state_enter],
    restart: :temporary

  defstruct [
    :application,
    :task_schema,
    :transition_schema,
    :token_table,
    :workitem_table
  ]

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()

  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type transition_schema :: WorkflowMetal.Storage.Schema.Transition.t()

  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()
  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()
  @type task_schema :: WorkflowMetal.Storage.Schema.Task.t()
  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()

  @type t :: %__MODULE__{
          application: application,
          task_schema: task_schema,
          transition_schema: transition_schema,
          token_table: :ets.tid(),
          workitem_table: :ets.tid()
        }

  @type options :: [
          name: term(),
          task_schema: task_schema()
        ]

  @type on_lock_tokens ::
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
    WorkflowMetal.Registration.via_tuple(
      application,
      name(task_schema)
    )
  end

  @doc """
  Offer a token.
  """
  @spec offer_token(:gen_statem.server_ref(), {place_id, token_id}) :: :ok
  def offer_token(task_server, {place_id, token_id}) do
    GenStateMachine.cast(task_server, {:offer_token, {place_id, token_id}})
  end

  @doc """
  Withdraw a token.
  """
  @spec withdraw_token(:gen_statem.server_ref(), token_id) :: :ok
  def withdraw_token(task_server, token_id) do
    GenStateMachine.cast(task_server, {:withdraw_token, token_id})
  end

  @doc """
  Lock tokens, and return `:ok`.

  If tokens are already locked by the task, return `:ok` too.

  When the task is not enabled, return `{:error, :task_not_enabled}`.
  When fail to lock tokens, return `{:error, :tokens_not_available}`.
  """
  @spec lock_tokens(:gen_statem.server_ref()) :: on_lock_tokens
  def lock_tokens(task_server) do
    GenStateMachine.call(task_server, :lock_tokens)
  end

  @doc """
  Mark a workitem completed.
  """
  @spec complete_workitem(:gen_statem.server_ref(), workitem_id) :: :ok
  def complete_workitem(task_server, workitem_id) do
    GenStateMachine.cast(task_server, {:complete_workitem, workitem_id})
  end

  @doc """
  Mark a workitem abandoned.
  """
  @spec abandon_workitem(:gen_statem.server_ref(), workitem_id) :: :ok
  def abandon_workitem(task_server, workitem_id) do
    GenStateMachine.cast(task_server, {:abandon_workitem, workitem_id})
  end

  # callbacks

  @impl GenStateMachine
  def init({{application, _workflow_id}, task_schema}) do
    %{
      state: state
    } = task_schema

    if state in [:abandoned, :completed] do
      {:stop, :normal}
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
        {
          :keep_state,
          data
        }

      # TODO: in case that restore from storage
      # {:state_timeout, 0, :execute_at_started}

      :executing ->
        # TODO: in case that restore from storage
        # fetch locked tokens
        {:keep_state, data}
    end
  end

  @impl GenStateMachine
  def handle_event(:enter, old_state, state, %__MODULE__{} = data) do
    case {old_state, state} do
      {:started, :executing} ->
        Logger.debug(fn -> "#{describe(data)} start executing." end)

        {:ok, data} = update_task(:executing, data)
        {:keep_state, data}

      {:executing, :completed} ->
        Logger.debug(fn -> "#{describe(data)} complete the execution." end)

        {:keep_state, data}

      {from, :abandoned} when from in [:started, :executing] ->
        Logger.debug(fn -> "#{describe(data)} has been abandoned." end)

        {:keep_state, data}
    end
  end

  @impl GenStateMachine
  def handle_event(:internal, :stop, :completed, %__MODULE__{} = data) do
    {:stop, :normal, data}
  end

  @impl GenStateMachine
  def handle_event(
        :cast,
        {:offer_token, {place_id, token_id}},
        :started,
        %__MODULE__{} = data
      ) do
    %{
      token_table: token_table
    } = data

    :ets.insert(token_table, {token_id, place_id, :free})

    {
      :keep_state,
      data,
      {:next_event, :cast, :execute}
    }
  end

  @impl GenStateMachine
  def handle_event(:cast, :offer_token, _state, %__MODULE__{}) do
    # ignore when the task is executing or completed
    :keep_state_and_data
  end

  @impl GenStateMachine
  def handle_event(
        :cast,
        {:withdraw_token, token_id},
        :started,
        %__MODULE__{} = data
      ) do
    %{
      token_table: token_table
    } = data

    :ets.delete(token_table, token_id)

    {
      :keep_state_and_data,
      {:next_event, :cast, :force_abandon}
    }
  end

  @impl GenStateMachine
  def handle_event(:cast, :withdraw_token, _state, %__MODULE__{}) do
    # ignore when the task is executing or completed
    :keep_state_and_data
  end

  @impl GenStateMachine
  def handle_event(:cast, :execute, :started, %__MODULE__{} = data) do
    with(
      {:ok, _token_ids} <- JoinController.task_enablement(data),
      {:ok, data} <- generate_workitem(data)
    ) do
      {:keep_state, data}
    else
      {:error, :task_not_enabled} ->
        :keep_state_and_data

      {:error, :tokens_not_available} ->
        # retry
        {
          :keep_state,
          data,
          {:next_event, :cast, :execute}
        }
    end
  end

  @impl GenStateMachine
  def handle_event(:cast, :complete, :executing, %__MODULE__{} = data) do
    with(
      :ok <- task_completion(data),
      {:ok, _token_ids, data} <- do_consume_tokens(data),
      {:ok, data} <- do_complete_task(data)
    ) do
      {
        :next_state,
        :completed,
        data,
        {:next_event, :internal, :stop}
      }
    else
      {:error, :task_not_completed} ->
        :keep_state_and_data

      _ ->
        :keep_state_and_data
    end
  end

  @impl GenStateMachine
  def handle_event(:cast, :force_abandon, state, %__MODULE__{} = data)
      when state in [:started, :executing] do
    case task_force_abandonment(data) do
      {:ok, data} ->
        {:ok, data} = do_abandon_workitems(data)

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
  def handle_event(:cast, :abandon, :executing, %__MODULE__{} = data) do
    case task_abandonment(data) do
      {:ok, data} ->
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
  def handle_event(
        :cast,
        {:complete_workitem, workitem_id},
        :executing,
        %__MODULE__{} = data
      ) do
    %{
      workitem_table: workitem_table
    } = data

    :ets.update_element(
      workitem_table,
      workitem_id,
      [
        {3, :completed}
      ]
    )

    {
      :keep_state_and_data,
      {:next_event, :cast, :complete}
    }
  end

  @impl GenStateMachine
  def handle_event(
        :cast,
        {:abandon_workitem, workitem_id},
        :executing,
        %__MODULE__{} = data
      ) do
    %{
      workitem_table: workitem_table
    } = data

    :ets.update_element(
      workitem_table,
      workitem_id,
      [
        {3, :abandoned}
      ]
    )

    {
      :keep_state_and_data,
      {:next_event, :cast, :abandon}
    }
  end

  @impl GenStateMachine
  def handle_event(:cast, _event_content, _state, %__MODULE__{}) do
    :keep_state_and_data
  end

  @impl GenStateMachine
  def handle_event({:call, from}, :lock_tokens, :started, %__MODULE__{} = data) do
    with(
      {:ok, token_ids} <- JoinController.task_enablement(data),
      {:ok, locked_token_schemas, data} <- do_lock_tokens(data, token_ids)
    ) do
      {
        :next_state,
        :executing,
        data,
        {:reply, from, {:ok, locked_token_schemas}}
      }
    else
      error ->
        {
          :keep_state_and_data,
          {:reply, from, error}
        }
    end
  end

  @impl GenStateMachine
  def handle_event({:call, from}, :lock_tokens, :executing, %__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id
      }
    } = data

    # TODO: fetch locked_tokens at init
    {:ok, locked_token_schemas} = WorkflowMetal.Storage.fetch_locked_tokens(application, task_id)

    {
      :keep_state,
      data,
      {:reply, from, {:ok, locked_token_schemas}}
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
      },
      workitem_table: workitem_table
    } = data

    {:ok, workitems} = WorkflowMetal.Storage.fetch_workitems(application, task_id)

    Enum.each(workitems, fn workitem ->
      :ets.insert(workitem_table, {workitem.id, workitem, workitem.state})
    end)

    # TODO: try to fire or complete task
    # if the task is enabled, then fire task
    # if the task is completed, then complete task
    {:ok, data}
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

  defp update_task(state_and_options, %__MODULE__{} = data) do
    %{
      application: application,
      task_schema: task_schema
    } = data

    {:ok, task_schema} =
      WorkflowMetal.Storage.update_task(
        application,
        task_schema.id,
        state_and_options
      )

    {:ok, %{data | task_schema: task_schema}}
  end

  defp generate_workitem(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id,
        workflow_id: workflow_id,
        transition_id: transition_id,
        case_id: case_id
      }
    } = data

    workitem_params = %Schema.Workitem.Params{
      workflow_id: workflow_id,
      transition_id: transition_id,
      case_id: case_id,
      task_id: task_id
    }

    {:ok, workitem_schema} = WorkflowMetal.Storage.create_workitem(application, workitem_params)

    {:ok, _} =
      WorkflowMetal.Workitem.Supervisor.open_workitem(
        application,
        workitem_schema
      )

    {:ok, data}
  end

  defp do_lock_tokens(%__MODULE__{} = data, token_ids) do
    %{
      task_schema: %Schema.Task{
        id: task_id
      },
      token_table: token_table
    } = data

    with(
      {:ok, locked_token_schemas} <-
        WorkflowMetal.Case.Case.lock_tokens(
          case_server(data),
          token_ids,
          task_id
        )
    ) do
      Enum.each(token_ids, &:ets.update_element(token_table, &1, [{3, :locked}]))

      {:ok, locked_token_schemas, data}
    end
  end

  defp task_completion(%__MODULE__{} = data) do
    data
    |> Map.fetch!(:workitem_table)
    |> :ets.tab2list()
    |> Enum.all?(fn
      {_workitem_id, _workitem, :completed} -> true
      _ -> false
    end)
    |> case do
      true -> :ok
      false -> {:error, :task_not_completed}
    end
  end

  defp do_consume_tokens(%__MODULE__{} = data) do
    %{
      task_schema: %Schema.Task{
        id: task_id
      },
      token_table: token_table
    } = data

    token_ids = :ets.select(token_table, [{{:"$1", :_, :_}, [], [:"$1"]}])

    {:ok, _tokens} =
      WorkflowMetal.Case.Case.consume_tokens(
        case_server(data),
        token_ids,
        task_id
      )

    {:ok, token_ids, data}
  end

  defp do_complete_task(%__MODULE__{} = data) do
    {:ok, token_payload} = build_token_payload(data)

    {:ok, token_params_list} = SplitController.issue_tokens(data, token_payload)

    {:ok, _tokens} = WorkflowMetal.Case.Case.issue_tokens(case_server(data), token_params_list)

    update_task({:completed, token_payload}, data)
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

  defp task_abandonment(%__MODULE__{} = data) do
    %{
      workitem_table: workitem_table
    } = data

    workitem_table
    |> :ets.tab2list()
    |> Enum.all?(fn {_workitem_id, _workitem, workitem_state} ->
      workitem_state === :abandoned
    end)
    |> case do
      true -> {:ok, data}
      false -> {:error, :task_not_abandoned}
    end
  end

  defp task_force_abandonment(%__MODULE__{} = data) do
    %{
      token_table: token_table
    } = data

    token_table
    |> :ets.tab2list()
    |> case do
      [] -> {:ok, data}
      [_ | _] -> {:error, :task_not_force_abandoned}
    end
  end

  defp do_abandon_workitems(%__MODULE__{} = data) do
    %{
      application: application,
      workitem_table: workitem_table
    } = data

    workitem_table
    |> :ets.tab2list()
    |> Enum.each(fn
      {_workitem_id, workitem, state} when state in [:created, :started] ->
        workitem_server =
          WorkflowMetal.Workitem.Workitem.via_name(
            application,
            workitem
          )

        :ok = WorkflowMetal.Workitem.Workitem.abandon(workitem_server)

      _ ->
        :skip
    end)

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

    "Task<#{task_id}@#{workflow_id}/#{transition_id}/#{case_id}>"
  end

  defp case_server(%__MODULE__{} = data) do
    %{
      application: application,
      task_schema: %Schema.Task{
        workflow_id: workflow_id,
        case_id: case_id
      }
    } = data

    WorkflowMetal.Case.Case.via_name(application, {workflow_id, case_id})
  end
end
