defmodule WorkflowMetal.Storage.Adapters.InMemory do
  @moduledoc """
  An in-memory storage adapter useful for testing as no persistence provided.

  ## Storage
  The data of `:workflow_table` ETS table format:
      {workflow_id, workflow_schema}

  The data of `:arc_table` ETS table format:
      {arc_id, arc_schema, {workflow_id, place_id, transition_id, direction}}

  The data of `:place_table` ETS table format:
      {place_id, place_schema, {place_type, workflow_id}}

  The data of `:transition_table` ETS table format:
      {transition_id, transition_schema, workflow_id}

  The data of `:case_table` ETS table format:
      {case_id, case_schema, {case_state, workflow_id}}

  The data of `:task_table` ETS table format:
      {task_id, task_schema, {task_state, workflow_id, transition_id, case_id}}

  The data of `:token_table` ETS table format:
      {token_id, token_schema, {workflow_id, case_id, place_id, produced_by_task_id, locked_by_task_id, state}}

  The data of `:workitem_table` ETS table format:
      {workitem_id, workitem_schema, {workflow_id, case_id, task_id}}
  """

  alias WorkflowMetal.Utils.ETS, as: ETSUtil

  alias WorkflowMetal.Storage.Schema

  @behaviour WorkflowMetal.Storage.Adapter

  use GenServer

  defmodule State do
    @moduledoc false

    use TypedStruct

    typedstruct do
      field :name, atom()
      field :workflow_table, :ets.tid()
      field :arc_table, :ets.tid()
      field :place_table, :ets.tid()
      field :transition_table, :ets.tid()
      field :case_table, :ets.tid()
      field :token_table, :ets.tid()
      field :task_table, :ets.tid()
      field :workitem_table, :ets.tid()
    end
  end

  @type application :: WorkflowMetal.Application.t()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type task_schema :: WorkflowMetal.Storage.Schema.Task.t()
  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()

  @doc false
  def start_link(opts \\ []) do
    {start_opts, _in_memory_opts} = Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt])

    state = %State{
      name: Keyword.fetch!(opts, :name)
    }

    GenServer.start_link(__MODULE__, state, start_opts)
  end

  @impl GenServer
  def init(%State{} = state) do
    {
      :ok,
      %{
        state
        | workflow_table: :ets.new(:workflow_table, [:set, :private]),
          place_table: :ets.new(:place_table, [:set, :private]),
          transition_table: :ets.new(:transition_table, [:set, :private]),
          arc_table: :ets.new(:arc_table, [:set, :private]),
          case_table: :ets.new(:case_table, [:set, :private]),
          task_table: :ets.new(:task_table, [:set, :private]),
          token_table: :ets.new(:token_table, [:set, :private]),
          workitem_table: :ets.new(:workitem_table, [:set, :private])
      }
    }
  end

  @impl WorkflowMetal.Storage.Adapter
  def child_spec(application, config) do
    {storage_name, config} = parse_config(application, config)

    child_spec = %{
      id: storage_name,
      start: {__MODULE__, :start_link, [config]}
    }

    {:ok, child_spec, %{name: storage_name}}
  end

  defp parse_config(application, config) do
    case Keyword.get(config, :name) do
      nil ->
        name = Module.concat([application, Storage])

        {name, Keyword.put(config, :name, name)}

      name when is_atom(name) ->
        {name, config}

      invalid ->
        raise ArgumentError,
          message:
            "expected :name option to be an atom but got: " <>
              inspect(invalid)
    end
  end

  # Util
  @impl WorkflowMetal.Storage.Adapter
  def generate_id(_adapter_meta, _schema_type, _options) do
    :erlang.unique_integer([:positive, :monotonic])
  end

  # Workflow

  @impl WorkflowMetal.Storage.Adapter
  def create_workflow(adapter_meta, workflow_params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:create_workflow, workflow_params})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_workflow(adapter_meta, workflow_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_workflow, workflow_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def delete_workflow(adapter_meta, workflow_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:delete_workflow, workflow_id})
  end

  # Places, Transitions, and Arcs

  @impl WorkflowMetal.Storage.Adapter
  def fetch_edge_places(adapter_meta, workflow_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_edge_places, workflow_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_places(adapter_meta, transition_id, arc_direction) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_places, transition_id, arc_direction})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_transition(adapter_meta, transition_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_transition, transition_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_transitions(adapter_meta, place_id, arc_direction) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_transitions, place_id, arc_direction})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_arcs(adapter_meta, arc_beginning, arc_direction) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_arcs, arc_beginning, arc_direction})
  end

  # Case

  @impl WorkflowMetal.Storage.Adapter
  def insert_case(adapter_meta, case_schema) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:insert_case, case_schema})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_case(adapter_meta, case_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_case, case_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def update_case(adapter_meta, case_id, params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:update_case, case_id, params})
  end

  # Task

  @impl WorkflowMetal.Storage.Adapter
  def insert_task(adapter_meta, task_schema) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:insert_task, task_schema})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_task(adapter_meta, task_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_task, task_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_tasks(adapter_meta, case_id, options) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_tasks, case_id, options})
  end

  @impl WorkflowMetal.Storage.Adapter
  def update_task(adapter_meta, task_id, params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:update_task, task_id, params})
  end

  # Token

  @impl WorkflowMetal.Storage.Adapter
  def issue_token(adapter_meta, token_schema) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:issue_token, token_schema})
  end

  @impl WorkflowMetal.Storage.Adapter
  def lock_tokens(adapter_meta, token_ids, task_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:lock_tokens, token_ids, task_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def unlock_tokens(adapter_meta, task_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:unlock_tokens, task_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def consume_tokens(adapter_meta, task_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:consume_tokens, task_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_tokens(adapter_meta, case_id, options) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_tokens, case_id, options})
  end

  # Workitem

  @impl WorkflowMetal.Storage.Adapter
  def insert_workitem(adapter_meta, workitem_schema) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:insert_workitem, workitem_schema})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_workitem(adapter_meta, workitem_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_workitem, workitem_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_workitems(adapter_meta, task_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_workitems, task_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def update_workitem(adapter_meta, workitem_id, params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:update_workitem, workitem_id, params})
  end

  @doc """
  Reset state.
  """
  def reset!(application) do
    {_adapter, adapter_meta} = WorkflowMetal.Application.storage_adapter(application)
    storage = storage_name(adapter_meta)

    GenServer.call(storage, :reset!)
  end

  @doc """
  List tasks of the workflow.
  """
  @spec list_tasks(application, workflow_id) :: {:ok, [task_schema]}
  def list_tasks(application, workflow_id) do
    {_adapter, adapter_meta} = WorkflowMetal.Application.storage_adapter(application)
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:list_tasks, workflow_id})
  end

  @doc """
  List workitems of the workflow.
  """
  @spec list_workitems(application, workflow_id) :: {:ok, [workitem_schema]}
  def list_workitems(application, workflow_id) do
    {_adapter, adapter_meta} = WorkflowMetal.Application.storage_adapter(application)
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:list_workitems, workflow_id})
  end

  @impl GenServer
  def handle_call(
        {:create_workflow, workflow_params},
        _from,
        %State{} = state
      ) do
    {:ok, workflow_schema} = persist_workflow(workflow_params, state)

    {:reply, {:ok, workflow_schema}, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_workflow, workflow_id},
        _from,
        %State{} = state
      ) do
    reply = find_workflow(workflow_id, state)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:delete_workflow, workflow_id},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, workflow_schema} <- find_workflow(workflow_id, state)) do
        :workflow
        |> get_table(state)
        |> :ets.delete(workflow_schema.id)

        :ok
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_arcs, {:transition, transition_id}, arc_direction},
        _from,
        %State{} = state
      ) do
    arc_direction = reversed_arc_direction(arc_direction)

    reply =
      with({:ok, transition_schema} <- find_transition(transition_id, state)) do
        arcs =
          :arc
          |> get_table(state)
          |> :ets.select([
            {{:_, :"$1", {:_, :_, transition_schema.id, arc_direction}}, [], [:"$1"]}
          ])

        {:ok, arcs}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_edge_places, workflow_id},
        _from,
        %State{} = state
      ) do
    reply =
      with(
        {:ok, start_place} <- find_edge_place(workflow_id, :start, state),
        {:ok, end_place} <- find_edge_place(workflow_id, :end, state)
      ) do
        {:ok, {start_place, end_place}}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_places, transition_id, arc_direction},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, transition_schema} <- find_transition(transition_id, state)) do
        direction = reversed_arc_direction(arc_direction)

        :arc
        |> get_table(state)
        |> :ets.select([
          {
            {:_, :_, {transition_schema.workflow_id, :"$1", transition_schema.id, direction}},
            [],
            [:"$1"]
          }
        ])
        |> Enum.reduce({:ok, []}, fn place_id, {:ok, places} ->
          {:ok, place_schema} = find_place(place_id, state)
          {:ok, [place_schema | places]}
        end)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_transition, transition_id},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, transition_schema} <- find_transition(transition_id, state)) do
        {:ok, transition_schema}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_transitions, place_id, arc_direction},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, place_schema} <- find_place(place_id, state)) do
        :arc
        |> get_table(state)
        |> :ets.select([
          {
            {:_, :_, {place_schema.workflow_id, place_schema.id, :"$1", arc_direction}},
            [],
            [:"$1"]
          }
        ])
        |> Enum.reduce({:ok, []}, fn transition_id, {:ok, transitions} ->
          {:ok, transition_schema} = find_transition(transition_id, state)
          {:ok, [transition_schema | transitions]}
        end)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:insert_case, case_schema},
        _from,
        %State{} = state
      ) do
    %{workflow_id: workflow_id} = case_schema

    reply =
      with({:ok, _workflow_schema} <- find_workflow(workflow_id, state)) do
        persist_case(case_schema, state)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_case, case_id},
        _from,
        %State{} = state
      ) do
    reply = find_case(case_id, state)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:update_case, case_id, params},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, case_schema} <- find_case(case_id, state)) do
        do_update_case(case_schema, params, state)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:insert_task, task_schema},
        _from,
        %State{} = state
      ) do
    %{
      workflow_id: workflow_id,
      transition_id: transition_id,
      case_id: case_id
    } = task_schema

    reply =
      with(
        {:ok, _workflow_schema} <- find_workflow(workflow_id, state),
        {:ok, _transition_schema} <- find_transition(transition_id, state),
        {:ok, _case_schema} <- find_case(case_id, state)
      ) do
        persist_task(task_schema, state)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_task, task_id},
        _from,
        %State{} = state
      ) do
    reply = find_task(task_id, state)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_tasks, case_id, options},
        _from,
        %State{} = state
      ) do
    reply = do_fetch_tasks(case_id, options, state)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:update_task, task_id, params},
        _from,
        %State{} = state
      ) do
    case find_task(task_id, state) do
      {:ok, task_schema} ->
        task_schema = struct(task_schema, params)

        {:ok, state} = upsert_task(task_schema, state)

        {:reply, {:ok, task_schema}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call(
        {:issue_token, token_schema},
        _from,
        %State{} = state
      ) do
    %{
      workflow_id: workflow_id,
      case_id: case_id,
      place_id: place_id,
      produced_by_task_id: produced_by_task_id
    } = token_schema

    reply =
      with(
        {:ok, _workflow_schema} <- find_workflow(workflow_id, state),
        {:ok, _case_schema} <- find_case(case_id, state),
        {:ok, _place_schema} <- find_place(place_id, state),
        {:ok, _produced_by_task} <- find_produced_by_task(produced_by_task_id, state)
      ) do
        {:ok, _state} = upsert_token(token_schema, state)

        {:ok, token_schema}
      else
        {:error, :task_not_found} ->
          {:error, :produced_by_task_not_found}

        reply ->
          reply
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:lock_tokens, token_ids, task_id},
        _from,
        %State{} = state
      ) do
    reply =
      with(
        {:ok, task_schema} <- find_task(task_id, state),
        {:ok, tokens} <- prepare_lock_tokens(token_ids, task_schema, state)
      ) do
        do_lock_tokens(tokens, task_schema, state)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:unlock_tokens, task_id},
        _from,
        %State{} = state
      ) do
    reply =
      case find_task(task_id, state) do
        {:ok, %Schema.Task{case_id: case_id}} ->
          {:ok, tokens} =
            find_tokens(
              case_id,
              [states: [:locked], locked_by_task_id: task_id],
              state
            )

          do_unlock_tokens(tokens, state)

        {:error, :task_not_found} ->
          :ok
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:consume_tokens, {case_id, :termination}},
        _from,
        %State{} = state
      ) do
    reply =
      with(
        {:ok, %Schema.Case{id: case_id}} <- find_case(case_id, state),
        {:ok, [token]} <- find_tokens(case_id, [states: [:free]], state)
      ) do
        do_consume_termination_token(token, state)
      else
        {:ok, _} -> {:error, :tokens_not_available}
        reply -> reply
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:consume_tokens, task_id},
        _from,
        %State{} = state
      ) do
    reply =
      with(
        {:ok, %Schema.Task{case_id: case_id} = task_schema} <- find_task(task_id, state),
        {:ok, tokens} <-
          find_tokens(case_id, [states: [:locked], locked_by_task_id: task_id], state)
      ) do
        do_consume_tokens(tokens, task_schema, state)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_tokens, case_id, options},
        _from,
        %State{} = state
      ) do
    reply = find_tokens(case_id, options, state)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:insert_workitem, workitem_schema},
        _from,
        %State{} = state
      ) do
    %{
      workflow_id: workflow_id,
      case_id: case_id,
      task_id: task_id
    } = workitem_schema

    reply =
      with(
        {:ok, _workflow_schema} <- find_workflow(workflow_id, state),
        {:ok, _case_schema} <- find_case(case_id, state),
        {:ok, _task_schema} <- find_task(task_id, state)
      ) do
        persist_workitem(workitem_schema, state)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_workitem, workitem_id},
        _from,
        %State{} = state
      ) do
    reply = find_workitem(workitem_id, state)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_workitems, task_id},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, task_schema} <- find_task(task_id, state)) do
        {
          :ok,
          :workitem
          |> get_table(state)
          |> :ets.select([
            {
              {:_, :"$1", {task_schema.workflow_id, task_schema.case_id, task_schema.id}},
              [],
              [:"$1"]
            }
          ])
        }
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:update_workitem, workitem_id, params},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, workitem_schema} <- find_workitem(workitem_id, state)) do
        workitem_schema = struct(workitem_schema, params)

        {:ok, _state} = upsert_workitem(workitem_schema, state)

        {:ok, workitem_schema}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(:reset!, _from, %State{} = state) do
    state
    |> Map.keys()
    |> Stream.filter(fn key ->
      key
      |> to_string()
      |> String.ends_with?("_table")
    end)
    |> Stream.map(&Map.get(state, &1))
    |> Stream.each(&:ets.delete_all_objects/1)
    |> Stream.run()

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:list_tasks, workflow_id}, _from, %State{} = state) do
    tasks =
      :task
      |> get_table(state)
      |> :ets.select([{{:_, :"$1", {:_, workflow_id, :_, :_}}, [], [:"$1"]}])
      |> Enum.sort(&(&1.id <= &2.id))

    {:reply, {:ok, tasks}, state}
  end

  @impl GenServer
  def handle_call({:list_workitems, workflow_id}, _from, %State{} = state) do
    workitems =
      :workitem
      |> get_table(state)
      |> :ets.select([{{:_, :"$1", {workflow_id, :_, :_}}, [], [:"$1"]}])
      |> Enum.sort(&(&1.id <= &2.id))

    {:reply, {:ok, workitems}, state}
  end

  defp persist_workflow(workflow_params, %State{} = state) do
    workflow_table = get_table(:workflow, state)

    workflow_id = Map.get(workflow_params, :id) |> make_id()

    workflow_schema =
      struct(
        Schema.Workflow,
        workflow_params |> Map.from_struct() |> Map.put(:id, workflow_id)
      )

    :ets.insert(workflow_table, {workflow_schema.id, workflow_schema})

    place_schemas =
      persist_places(
        Map.get(workflow_params, :places),
        state,
        workflow_id: workflow_schema.id
      )

    transition_schemas =
      persist_transitions(
        Map.get(workflow_params, :transitions),
        state,
        workflow_id: workflow_schema.id
      )

    persist_arcs(
      Map.get(workflow_params, :arcs),
      state,
      workflow_id: workflow_schema.id,
      place_schemas: place_schemas,
      transition_schemas: transition_schemas
    )

    {:ok, workflow_schema}
  end

  defp find_workflow(workflow_id, %State{} = state) do
    :workflow
    |> get_table(state)
    |> :ets.select([{{workflow_id, :"$1"}, [], [:"$1"]}])
    |> case do
      [workflow] -> {:ok, workflow}
      _ -> {:error, :workflow_not_found}
    end
  end

  defp persist_place(place_params, %State{} = state, options) do
    place_table = get_table(:place, state)
    workflow_id = Keyword.fetch!(options, :workflow_id)

    place_id = Map.get(place_params, :id) |> make_id()

    place_schema =
      struct(
        Schema.Place,
        place_params
        |> Map.from_struct()
        |> Map.put(:id, place_id)
        |> Map.put(:workflow_id, workflow_id)
      )

    :ets.insert(
      place_table,
      {
        place_schema.id,
        place_schema,
        {
          place_schema.type,
          place_schema.workflow_id
        }
      }
    )

    {:ok, place_schema}
  end

  defp find_place(place_id, %State{} = state) do
    :place
    |> get_table(state)
    |> :ets.select([{{place_id, :"$1", :_}, [], [:"$1"]}])
    |> case do
      [place] -> {:ok, place}
      _ -> {:error, :place_not_found}
    end
  end

  defp find_edge_place(workflow_id, place_type, %State{} = state) do
    :place
    |> get_table(state)
    |> :ets.select([{{:_, :"$1", {place_type, workflow_id}}, [], [:"$1"]}])
    |> case do
      [place] -> {:ok, place}
      _ -> {:error, :workflow_not_found}
    end
  end

  defp persist_places(places_params, %State{} = state, options) do
    Enum.into(places_params, %{}, fn place_params ->
      {:ok, place_schema} = persist_place(place_params, state, options)

      {place_params.id, place_schema}
    end)
  end

  defp persist_transition(transition_params, %State{} = state, options) do
    transition_table = get_table(:transition, state)
    workflow_id = Keyword.fetch!(options, :workflow_id)

    transition_id = Map.get(transition_params, :id) |> make_id()

    transition_schema =
      struct(
        Schema.Transition,
        transition_params
        |> Map.from_struct()
        |> Map.put(:id, transition_id)
        |> Map.put(:workflow_id, workflow_id)
      )

    :ets.insert(
      transition_table,
      {
        transition_schema.id,
        transition_schema,
        transition_schema.workflow_id
      }
    )

    {:ok, transition_schema}
  end

  defp find_transition(transition_id, %State{} = state) do
    :transition
    |> get_table(state)
    |> :ets.select([{{transition_id, :"$1", :_}, [], [:"$1"]}])
    |> case do
      [transition] -> {:ok, transition}
      _ -> {:error, :transition_not_found}
    end
  end

  defp persist_transitions(transitions_params, %State{} = state, options) do
    Enum.into(transitions_params, %{}, fn transition_params ->
      {:ok, transition_schema} = persist_transition(transition_params, state, options)

      {transition_params.id, transition_schema}
    end)
  end

  defp persist_arc(arc_params, %State{} = state, options) do
    arc_table = get_table(:arc, state)
    workflow_id = Keyword.fetch!(options, :workflow_id)
    place_schemas = Keyword.fetch!(options, :place_schemas)
    transition_schemas = Keyword.fetch!(options, :transition_schemas)

    %{
      place_id: place_id,
      transition_id: transition_id
    } = arc_params

    arc_id = Map.get(arc_params, :id) |> make_id()

    arc_schema =
      struct(
        Schema.Arc,
        arc_params
        |> Map.from_struct()
        |> Map.put(:id, arc_id)
        |> Map.put(:workflow_id, workflow_id)
        |> Map.put(:place_id, place_schemas[place_id].id)
        |> Map.put(:transition_id, transition_schemas[transition_id].id)
      )

    :ets.insert(
      arc_table,
      {
        arc_schema.id,
        arc_schema,
        {
          arc_schema.workflow_id,
          arc_schema.place_id,
          arc_schema.transition_id,
          arc_schema.direction
        }
      }
    )

    {:ok, arc_schema}
  end

  defp persist_arcs(arcs_params, %State{} = state, options) do
    Enum.map(arcs_params, fn arc_params ->
      {:ok, arc_schema} = persist_arc(arc_params, state, options)

      arc_schema
    end)
  end

  defp persist_case(case_schema, %State{} = state) do
    case_table = get_table(:case, state)

    :ets.insert(
      case_table,
      {
        case_schema.id,
        case_schema,
        {
          case_schema.state,
          case_schema.workflow_id
        }
      }
    )

    {:ok, case_schema}
  end

  defp find_case(case_id, %State{} = state) do
    :case
    |> get_table(state)
    |> :ets.select([{{case_id, :"$1", :_}, [], [:"$1"]}])
    |> case do
      [case_schema] -> {:ok, case_schema}
      _ -> {:error, :case_not_found}
    end
  end

  defp do_update_case(
         %Schema.Case{} = case_schema,
         %{} = params,
         %State{} = state
       ) do
    case_table = get_table(:case, state)
    case_schema = struct(case_schema, params)

    true =
      :ets.update_element(
        case_table,
        case_schema.id,
        [
          {2, case_schema},
          {3, {case_schema.state, case_schema.workflow_id}}
        ]
      )

    {:ok, case_schema}
  end

  defp find_tokens(case_id, options, %State{} = state) do
    states_condition =
      ETSUtil.make_condition(
        Keyword.get(options, :states, []),
        :"$3",
        :in
      )

    locked_by_task_condition =
      case Keyword.get(options, :locked_by_task_id) do
        nil -> nil
        task_id -> {:"=:=", :"$2", task_id}
      end

    {
      :ok,
      :token
      |> get_table(state)
      |> :ets.select([
        {
          {:_, :"$1", {:_, case_id, :_, :_, :"$2", :"$3"}},
          List.wrap(ETSUtil.make_and([states_condition, locked_by_task_condition])),
          [:"$1"]
        }
      ])
    }
  end

  defp prepare_lock_tokens(token_ids, %Schema.Task{} = task_schema, %State{} = state) do
    free_tokens =
      task_schema.case_id
      |> find_tokens([states: [:free]], state)
      |> elem(1)
      |> Enum.into(%{}, &{&1.id, &1})

    Enum.reduce_while(token_ids, {:ok, []}, fn token_id, {:ok, tokens} ->
      case free_tokens[token_id] do
        nil ->
          {:halt, {:error, :tokens_not_available}}

        token ->
          {:cont, {:ok, [token | tokens]}}
      end
    end)
  end

  defp do_lock_tokens(tokens, %Schema.Task{} = task_schema, %State{} = state) do
    task_id = task_schema.id

    tokens =
      Enum.map(tokens, fn token ->
        token_schema = %{token | state: :locked, locked_by_task_id: task_id}

        {:ok, _state} = upsert_token(token_schema, state)

        token_schema
      end)

    {:ok, tokens}
  end

  defp do_unlock_tokens(tokens, %State{} = state) do
    tokens =
      Enum.map(tokens, fn token ->
        token_schema = %{token | state: :free, locked_by_task_id: nil}

        {:ok, _state} = upsert_token(token_schema, state)

        token_schema
      end)

    {:ok, tokens}
  end

  defp do_consume_tokens(tokens, %Schema.Task{} = task_schema, %State{} = state) do
    task_id = task_schema.id

    tokens =
      Enum.map(tokens, fn token ->
        token_schema = %{token | state: :consumed, consumed_by_task_id: task_id}

        {:ok, _state} = upsert_token(token_schema, state)

        token_schema
      end)

    {:ok, tokens}
  end

  defp do_consume_termination_token(token, %State{} = state) do
    token_schema = %{token | state: :consumed}
    {:ok, _state} = upsert_token(token_schema, state)

    {:ok, [token_schema]}
  end

  defp upsert_token(%Schema.Token{} = token_schema, %State{} = state) do
    true =
      :ets.insert(
        get_table(:token, state),
        {
          token_schema.id,
          token_schema,
          {
            token_schema.workflow_id,
            token_schema.case_id,
            token_schema.place_id,
            token_schema.produced_by_task_id,
            token_schema.locked_by_task_id,
            token_schema.state
          }
        }
      )

    {:ok, state}
  end

  defp persist_task(%Schema.Task{} = task_schema, %State{} = state) do
    task_table = get_table(:task, state)

    :ets.insert(
      task_table,
      {
        task_schema.id,
        task_schema,
        {
          task_schema.state,
          task_schema.workflow_id,
          task_schema.transition_id,
          task_schema.case_id
        }
      }
    )

    {:ok, task_schema}
  end

  defp find_produced_by_task(:genesis, %State{}), do: {:ok, nil}
  defp find_produced_by_task(task_id, %State{} = state), do: find_task(task_id, state)

  defp find_task(task_id, %State{} = state) do
    :task
    |> get_table(state)
    |> :ets.select([{{task_id, :"$1", :_}, [], [:"$1"]}])
    |> case do
      [task_schema] -> {:ok, task_schema}
      _ -> {:error, :task_not_found}
    end
  end

  defp do_fetch_tasks(case_id, options, %State{} = state) do
    states_condition =
      ETSUtil.make_condition(
        Keyword.get(options, :states, []),
        :"$2",
        :in
      )

    transition_condition =
      case Keyword.get(options, :transition_id) do
        nil -> nil
        task_id -> {:"=:=", :"$3", task_id}
      end

    {
      :ok,
      :task
      |> get_table(state)
      |> :ets.select([
        {
          {:_, :"$1", {:"$2", :_, :"$3", case_id}},
          List.wrap(ETSUtil.make_and([states_condition, transition_condition])),
          [:"$1"]
        }
      ])
    }
  end

  defp upsert_task(%Schema.Task{} = task_schema, %State{} = state) do
    true =
      :ets.insert(
        get_table(:task, state),
        {
          task_schema.id,
          task_schema,
          {
            task_schema.state,
            task_schema.workflow_id,
            task_schema.transition_id,
            task_schema.case_id
          }
        }
      )

    {:ok, state}
  end

  defp persist_workitem(workitem_schema, %State{} = state) do
    workitem_table = get_table(:workitem, state)

    :ets.insert(
      workitem_table,
      {
        workitem_schema.id,
        workitem_schema,
        {
          workitem_schema.workflow_id,
          workitem_schema.case_id,
          workitem_schema.task_id
        }
      }
    )

    {:ok, workitem_schema}
  end

  defp find_workitem(workitem_id, %State{} = state) do
    :workitem
    |> get_table(state)
    |> :ets.select([{{workitem_id, :"$1", :_}, [], [:"$1"]}])
    |> case do
      [workitem_schema] -> {:ok, workitem_schema}
      _ -> {:error, :workitem_not_found}
    end
  end

  defp upsert_workitem(%Schema.Workitem{} = workitem_schema, %State{} = state) do
    true =
      :ets.insert(
        get_table(:workitem, state),
        {
          workitem_schema.id,
          workitem_schema,
          {
            workitem_schema.workflow_id,
            workitem_schema.case_id,
            workitem_schema.task_id
          }
        }
      )

    {:ok, state}
  end

  defp get_table(table_type, %State{} = state) do
    table_name = String.to_existing_atom("#{table_type}_table")
    Map.fetch!(state, table_name)
  end

  defp storage_name(adapter_meta) when is_map(adapter_meta),
    do: Map.get(adapter_meta, :name)

  defp make_id, do: :erlang.unique_integer([:positive, :monotonic])
  defp make_id(nil), do: :erlang.unique_integer([:positive, :monotonic])
  defp make_id(id), do: :"#{inspect(id)}-#{:erlang.unique_integer([:positive, :monotonic])}"

  defp reversed_arc_direction(:in), do: :out
  defp reversed_arc_direction(:out), do: :in
end
