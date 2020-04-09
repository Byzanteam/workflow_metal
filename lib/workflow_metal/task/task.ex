defmodule WorkflowMetal.Task.Task do
  @moduledoc """
  A `GenServer` to hold tokens, execute conditions and generate `workitem`.

  ## Storage
  The data of `:token_table` is stored in ETS in the following format:
      {token_id :: token_id, place_id :: place_id, token_state :: token_state}

  The data of `:workitem_table` is stored in ETS in the following format:
      {workitem_id :: workitem_id, workitem_state :: workitem_state}
  """

  use GenServer

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
          task: task_schema()
        ]

  @type on_lock_tokens ::
          {:ok, nonempty_list(token_schema)}
          | {:error, :tokens_not_available}
          | {:error, :task_not_enabled}

  alias WorkflowMetal.Controller.Join, as: JoinController
  alias WorkflowMetal.Controller.Split, as: SplitController
  alias WorkflowMetal.Storage.Schema

  @doc false
  @spec start_link(workflow_identifier, options) :: GenServer.on_start()
  def start_link(workflow_identifier, options) do
    name = Keyword.fetch!(options, :name)
    task = Keyword.fetch!(options, :task)

    GenServer.start_link(
      __MODULE__,
      {workflow_identifier, task},
      name: name
    )
  end

  @doc false
  @spec name({workflow_id, case_id, transition_id, task_id}) :: term()
  def name({workflow_id, case_id, transition_id, task_id}) do
    {__MODULE__, {workflow_id, case_id, transition_id, task_id}}
  end

  @doc false
  @spec via_name(application, {workflow_id, case_id, transition_id, task_id}) :: term()
  def via_name(application, {workflow_id, case_id, transition_id, task_id}) do
    WorkflowMetal.Registration.via_tuple(
      application,
      name({workflow_id, case_id, transition_id, task_id})
    )
  end

  @doc """
  Offer a token.
  """
  @spec offer_token(GenServer.server(), place_id, token_id) :: :ok
  def offer_token(task_server, place_id, token_id) do
    GenServer.cast(task_server, {:offer_token, place_id, token_id})
  end

  @doc """
  Withdraw a token.
  """
  @spec withdraw_token(GenServer.server(), token_id) :: :ok
  def withdraw_token(task_server, token_id) do
    GenServer.cast(task_server, {:withdraw_token, token_id})
  end

  @doc """
  Lock tokens, and return `:ok`.

  If tokens are already locked by the task, return `:ok` too.

  When the task is not enabled, return `{:error, :task_not_enabled}`.
  When fail to lock tokens, return `{:error, :tokens_not_available}`.
  """
  @spec lock_tokens(GenServer.server()) :: on_lock_tokens
  def lock_tokens(task_server) do
    GenServer.call(task_server, :lock_tokens)
  end

  @doc """
  """
  @spec complete_workitem(GenServer.server(), workitem_id) :: :ok
  def complete_workitem(task_server, workitem_id) do
    GenServer.cast(task_server, {:complete_workitem, workitem_id})
  end

  # @doc """
  # """
  # @spec fail_workitem(GenServer.server(), workitem_id, error) :: :ok
  # def fail_workitem(task_server, workitem_id, error) do
  #   GenServer.call(task_server, {:fail_workitem, workitem_id, error})
  # end

  # callbacks

  @impl true
  def init({{application, _workflow_id}, task}) do
    {
      :ok,
      %__MODULE__{
        application: application,
        task_schema: task,
        token_table: :ets.new(:token_table, [:set, :private]),
        workitem_table: :ets.new(:workitem_table, [:set, :private])
      },
      {:continue, :fetch_transition}
    }
  end

  @impl true
  def handle_continue(:fetch_transition, %__MODULE__{} = state) do
    %{
      application: application,
      task_schema: %Schema.Task{
        transition_id: transition_id
      }
    } = state

    {:ok, transition_schema} = WorkflowMetal.Storage.fetch_transition(application, transition_id)

    {
      :noreply,
      %{state | transition_schema: transition_schema},
      {:continue, :fetch_workitems}
    }
  end

  @impl true
  def handle_continue(:fetch_workitems, %__MODULE__{} = state) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id
      },
      workitem_table: workitem_table
    } = state

    {:ok, workitems} = WorkflowMetal.Storage.fetch_workitems(application, task_id)

    Enum.each(workitems, fn workitem ->
      :ets.insert(workitem_table, {workitem.id, workitem.state})
    end)

    # TODO: try to fire or complete task
    # if the task is enabled, then fire task
    # if the task is completed, then complete task
    {:noreply, state}
  end

  @impl true
  def handle_continue(:fire_task, %__MODULE__{} = state) do
    with(
      {:ok, _token_ids} <- JoinController.task_enablement(state),
      {:ok, state} <- generate_workitem(state)
    ) do
      {:noreply, state}
    else
      {:error, :task_not_enabled} ->
        {:noreply, state}

      {:error, :tokens_not_available} ->
        # retry
        {:noreply, state, {:continue, :fire_task}}
    end
  end

  @impl true
  def handle_continue(:complete_task, %__MODULE__{} = state) do
    with(
      :ok <- task_completion(state),
      {:ok, _tokens} <- do_consume_tokens(state),
      {:ok, state} <- do_complete_task(state)
    ) do
      {:stop, :normal, state}
    else
      {:error, :task_not_completed} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(
        {:offer_token, place_id, token_id},
        %__MODULE__{task_schema: %Schema.Task{state: :started}} = state
      ) do
    %{token_table: token_table} = state
    :ets.insert(token_table, {token_id, place_id, :free})

    {:noreply, state, {:continue, :fire_task}}
  end

  @impl true
  def handle_cast({:offer_token, _place_id, _token_id}, %__MODULE__{} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:withdraw_token, token_id}, %__MODULE__{} = state) do
    %{token_table: token_table} = state
    :ets.delete(token_table, token_id)

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:complete_workitem, workitem_id},
        %__MODULE__{} = state
      ) do
    %{
      workitem_table: workitem_table
    } = state

    :ets.update_element(workitem_table, workitem_id, [{2, :completed}])

    {:noreply, state, {:continue, :complete_task}}
  end

  @impl true
  def handle_call(
        :lock_tokens,
        _from,
        %__MODULE__{task_schema: %Schema.Task{state: :started}} = state
      ) do
    reply =
      with(
        {:ok, token_ids} <- JoinController.task_enablement(state),
        {:ok, locked_token_schemas} <- do_lock_tokens(token_ids, state),
        {:ok, state} <- do_execute_task(state)
      ) do
        {:ok, locked_token_schemas, state}
      end

    case reply do
      {:ok, locked_token_schemas, state} ->
        {:reply, {:ok, locked_token_schemas}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(
        :lock_tokens,
        _from,
        %__MODULE__{task_schema: %Schema.Task{state: :executing}} = state
      ) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id
      }
    } = state

    # TODO: fetch locked_tokens at init
    {:ok, locked_token_schemas} = WorkflowMetal.Storage.fetch_locked_tokens(application, task_id)
    {:reply, {:ok, locked_token_schemas}, state}
  end

  # @impl true
  # def handle_call({:fail_workitem, workitem_id, _error}, %__MODULE__{} = state) do
  #   # TODO:
  #   # - update workitem state
  #   # - issue tokens
  #   # - refund tokens

  #   {:noreply, state}
  # end

  defp do_lock_tokens(token_ids, %__MODULE__{} = state) do
    %{
      task_schema: %{
        id: task_id
      },
      token_table: token_table
    } = state

    with(
      {:ok, locked_token_schemas} <-
        WorkflowMetal.Case.Case.lock_tokens(case_server(state), token_ids, task_id)
    ) do
      Enum.each(token_ids, &:ets.update_element(token_table, &1, [{3, :locked}]))

      {:ok, locked_token_schemas}
    end
  end

  defp generate_workitem(%__MODULE__{} = state) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id,
        workflow_id: workflow_id,
        transition_id: transition_id,
        case_id: case_id
      }
    } = state

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

    {:ok, state}
  end

  defp task_completion(%__MODULE__{} = state) do
    state
    |> Map.fetch!(:workitem_table)
    |> :ets.tab2list()
    |> Enum.all?(fn
      {_workitem_id, :completed} -> true
      _ -> false
    end)
    |> case do
      true -> :ok
      false -> {:error, :task_not_completed}
    end
  end

  defp do_consume_tokens(%__MODULE__{} = state) do
    %{
      task_schema: %{
        id: task_id
      },
      token_table: token_table
    } = state

    token_ids = :ets.select(token_table, [{{:"$1", :_, :_}, [], [:"$1"]}])

    :ok =
      WorkflowMetal.Case.Case.consume_tokens(
        case_server(state),
        token_ids,
        task_id
      )

    {:ok, token_ids}
  end

  defp do_complete_task(%__MODULE__{} = state) do
    %{
      application: application,
      task_schema: task_schema
    } = state

    {:ok, token_payload} = build_token_payload(state)

    {:ok, token_params_list} = SplitController.issue_tokens(state, token_payload)
    {:ok, _tokens} = WorkflowMetal.Case.Case.issue_tokens(case_server(state), token_params_list)

    {:ok, task_schema} =
      WorkflowMetal.Storage.complete_task(application, task_schema.id, token_payload)

    {:ok, %{state | task_schema: task_schema}}
  end

  defp do_execute_task(%__MODULE__{} = state) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id
      }
    } = state

    {:ok, task_schema} = WorkflowMetal.Storage.execute_task(application, task_id)

    {:ok, %{state | task_schema: task_schema}}
  end

  defp build_token_payload(%__MODULE__{} = state) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id
      },
      transition_schema: %Schema.Transition{
        executor: executor,
        executor_params: executor_params
      }
    } = state

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

  defp case_server(%__MODULE__{} = state) do
    %{
      application: application,
      task_schema: %{
        workflow_id: workflow_id,
        case_id: case_id
      }
    } = state

    WorkflowMetal.Case.Case.via_name(application, {workflow_id, case_id})
  end
end
