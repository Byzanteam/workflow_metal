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

  The data of `:token_table` ETS table format:
      {token_id, token_schema, {workflow_id, case_id, place_id, produced_by_task_id, locked_by_task_id, state}}

  The data of `:task_table` ETS table format:
      {task_id, task_schema, {workflow_id, transition_id, case_id}}

  The data of `:workitem_table` ETS table format:
      {workitem_id, workitem_schema, {workflow_id, case_id, task_id}}
  """

  alias WorkflowMetal.Storage.Schema

  @behaviour WorkflowMetal.Storage.Adapter

  use GenServer

  defmodule State do
    @moduledoc false

    defstruct [
      :name,
      :workflow_table,
      :arc_table,
      :place_table,
      :transition_table,
      :case_table,
      :token_table,
      :task_table,
      :workitem_table
    ]
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

  @impl WorkflowMetal.Storage.Adapter
  def fetch_arcs(adapter_meta, workflow_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_arcs, workflow_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_arcs(adapter_meta, transition_id, arc_direction) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_arcs, transition_id, arc_direction})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_places(adapter_meta, transition_id, arc_direction) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_places, transition_id, arc_direction})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_special_place(adapter_meta, workflow_id, place_type) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_place, workflow_id, place_type})
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
  def create_case(adapter_meta, case_params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:create_case, case_params})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_case(adapter_meta, case_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_case, case_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def activate_case(adapter_meta, case_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:activate_case, case_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def create_task(adapter_meta, task_params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:create_task, task_params})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_task(adapter_meta, task_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_task, task_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_task(adapter_meta, case_id, transition_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_task, case_id, transition_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def complete_task(adapter_meta, task_id, token_payload) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:complete_task, task_id, token_payload})
  end

  @impl WorkflowMetal.Storage.Adapter
  def issue_token(adapter_meta, token_params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:issue_token, token_params})
  end

  @impl WorkflowMetal.Storage.Adapter
  def lock_token(adapter_meta, token_id, task_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:lock_token, token_id, task_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_tokens(adapter_meta, case_id, token_states) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_tokens, case_id, token_states})
  end

  @impl WorkflowMetal.Storage.Adapter
  def consume_tokens(adapter_meta, token_ids, task_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:consume_tokens, token_ids, task_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_locked_tokens(adapter_meta, task_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_locked_tokens, task_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def create_workitem(adapter_meta, workitem_params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:create_workitem, workitem_params})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_workitems(adapter_meta, task_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_workitems, task_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def start_workitem(adapter_meta, workitem_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:start_workitem, workitem_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def complete_workitem(adapter_meta, workitem_id, workitem_output) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:complete_workitem, workitem_id, workitem_output})
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
        {:fetch_arcs, workflow_id},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, workflow_schema} <- find_workflow(workflow_id, state)) do
        :arc
        |> get_table(state)
        |> :ets.select([{{:_, :"$1", {workflow_schema.id, :_, :_, :_}}, [], [:"$1"]}])
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_arcs, transition_id, arc_direction},
        _from,
        %State{} = state
      ) do
    arc_direction = reversed_arc_direction(arc_direction)

    reply =
      with({:ok, transition_schema} <- find_transition(transition_id, state)) do
        :arc
        |> get_table(state)
        |> :ets.select([{{:_, :"$1", {:_, :_, transition_schema.id, arc_direction}}, [], [:"$1"]}])
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
        {:fetch_place, workflow_id, place_type},
        _from,
        %State{} = state
      ) do
    reply = find_place_by_type(workflow_id, place_type, state)

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
        {:create_case, case_params},
        _from,
        %State{} = state
      ) do
    %{workflow_id: workflow_id} = case_params

    reply =
      with({:ok, workflow_schema} <- find_workflow(workflow_id, state)) do
        persist_case(case_params, state, workflow_id: workflow_schema.id)
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
        {:activate_case, case_id},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, case_schema} <- find_case(case_id, state)) do
        do_activate_case(case_schema, state)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:create_task, task_params},
        _from,
        %State{} = state
      ) do
    %{
      workflow_id: workflow_id,
      transition_id: transition_id,
      case_id: case_id
    } = task_params

    reply =
      with(
        {:ok, workflow_schema} <- find_workflow(workflow_id, state),
        {:ok, transition_schema} <- find_transition(transition_id, state),
        {:ok, case_schema} <- find_case(case_id, state)
      ) do
        persist_task(
          task_params,
          state,
          workflow_id: workflow_schema.id,
          transition_id: transition_schema.id,
          case_id: case_schema.id
        )
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
        {:fetch_task, case_id, transition_id},
        _from,
        %State{} = state
      ) do
    reply = find_task_by(case_id, transition_id, state)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:complete_task, task_id, token_payload},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, task_schema} <- find_task(task_id, state)) do
        do_complete_task(task_schema, token_payload, state)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:issue_token, token_params},
        _from,
        %State{} = state
      ) do
    %{
      workflow_id: workflow_id,
      case_id: case_id,
      place_id: place_id,
      produced_by_task_id: produced_by_task_id
    } = token_params

    reply =
      with(
        {:ok, workflow_schema} <- find_workflow(workflow_id, state),
        {:ok, case_schema} <- find_case(case_id, state),
        {:ok, place_schema} <- find_place(place_id, state),
        {:ok, produced_by_task} <- find_produced_by_task(produced_by_task_id, state)
      ) do
        persist_token(
          token_params,
          state,
          workflow_id: workflow_schema.id,
          case_id: case_schema.id,
          place_id: place_schema.id,
          produced_by_task_id: produced_by_task && produced_by_task.id
        )
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
        {:lock_token, token_id, task_id},
        _from,
        %State{} = state
      ) do
    reply =
      with(
        {:ok, task_schema} <- find_task(task_id, state),
        {:ok, token_schema} <- find_token(token_id, state)
      ) do
        do_lock_token(
          token_schema,
          task_schema,
          state
        )
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_tokens, case_id, token_states},
        _from,
        %State{} = state
      ) do
    reply = find_tokens(case_id, token_states, state)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:consume_tokens, token_ids, task_id},
        _from,
        %State{} = state
      ) do
    {:ok, task_schema} = find_task(task_id, state)

    tokens =
      Enum.map(token_ids, fn token_id ->
        with(
          {:ok, token_schema} <- find_token(token_id, state),
          {:ok, token_schema} <-
            do_consume_token(token_schema, task_schema.id, state)
        ) do
          token_schema
        else
          _ ->
            raise ArgumentError,
                  "the token(#{inspect(token_id)}) should be consumed by the task(#{
                    inspect(task_id)
                  })."
        end
      end)

    {:reply, {:ok, tokens}, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_locked_tokens, task_id},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, task_schema} <- find_task(task_id, state)) do
        {
          :ok,
          :token
          |> get_table(state)
          |> :ets.select([
            {
              {:_, :"$1", {task_schema.workflow_id, :_, :_, :_, task_schema.id, :locked}},
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
        {:create_workitem, workitem_params},
        _from,
        %State{} = state
      ) do
    %{
      workflow_id: workflow_id,
      case_id: case_id,
      task_id: task_id
    } = workitem_params

    reply =
      with(
        {:ok, workflow_schema} <- find_workflow(workflow_id, state),
        {:ok, case_schema} <- find_case(case_id, state),
        {:ok, task_schema} <- find_task(task_id, state)
      ) do
        persist_workitem(
          workitem_params,
          state,
          workflow_id: workflow_schema.id,
          case_id: case_schema.id,
          task_id: task_schema.id
        )
      end

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
        {:start_workitem, workitem_id},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, workitem_schema} <- find_workitem(workitem_id, state)) do
        do_start_workitem(
          workitem_schema,
          state
        )
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:complete_workitem, workitem_id, workitem_output},
        _from,
        %State{} = state
      ) do
    reply =
      with({:ok, workitem_schema} <- find_workitem(workitem_id, state)) do
        do_complete_workitem(
          workitem_schema,
          workitem_output,
          state
        )
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
      |> :ets.select([{{:_, :"$1", {workflow_id, :_, :_}}, [], [:"$1"]}])

    {:reply, {:ok, tasks}, state}
  end

  @impl GenServer
  def handle_call({:list_workitems, workflow_id}, _from, %State{} = state) do
    workitems =
      :workitem
      |> get_table(state)
      |> :ets.select([{{:_, :"$1", {workflow_id, :_, :_}}, [], [:"$1"]}])

    {:reply, {:ok, workitems}, state}
  end

  defp persist_workflow(workflow_params, %State{} = state) do
    workflow_table = get_table(:workflow, state)

    workflow_schema =
      struct(
        Schema.Workflow,
        workflow_params |> Map.from_struct() |> Map.put(:id, make_id())
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

    place_schema =
      struct(
        Schema.Place,
        place_params
        |> Map.from_struct()
        |> Map.put(:id, make_id())
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

  defp find_place_by_type(workflow_id, place_type, %State{} = state) do
    :place
    |> get_table(state)
    |> :ets.select([{{:_, :"$1", {place_type, workflow_id}}, [], [:"$1"]}])
    |> case do
      [place] -> {:ok, place}
      _ -> {:error, :place_not_found}
    end
  end

  defp persist_places(places_params, %State{} = state, options) do
    Enum.into(places_params, %{}, fn place_params ->
      {:ok, place_schema} = persist_place(place_params, state, options)

      {place_params.rid, place_schema}
    end)
  end

  defp persist_transition(transition_params, %State{} = state, options) do
    transition_table = get_table(:transition, state)
    workflow_id = Keyword.fetch!(options, :workflow_id)

    transition_schema =
      struct(
        Schema.Transition,
        transition_params
        |> Map.from_struct()
        |> Map.put(:id, make_id())
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

      {transition_params.rid, transition_schema}
    end)
  end

  defp persist_arc(arc_params, %State{} = state, options) do
    arc_table = get_table(:arc, state)
    workflow_id = Keyword.fetch!(options, :workflow_id)
    place_schemas = Keyword.fetch!(options, :place_schemas)
    transition_schemas = Keyword.fetch!(options, :transition_schemas)

    %{
      place_rid: place_rid,
      transition_rid: transition_rid
    } = arc_params

    arc_schema =
      struct(
        Schema.Arc,
        arc_params
        |> Map.from_struct()
        |> Map.put(:id, make_id())
        |> Map.put(:workflow_id, workflow_id)
        |> Map.put(:place_id, place_schemas[place_rid].id)
        |> Map.put(:transition_id, transition_schemas[transition_rid].id)
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

  defp persist_case(case_params, %State{} = state, options) do
    case_table = get_table(:case, state)
    workflow_id = Keyword.fetch!(options, :workflow_id)

    case_schema =
      struct(
        Schema.Case,
        case_params
        |> Map.from_struct()
        |> Map.put(:id, make_id())
        |> Map.put(:workflow_id, workflow_id)
      )

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

  defp do_activate_case(
         %Schema.Case{state: :active} = case_schema,
         %State{} = _state
       ) do
    {:ok, case_schema}
  end

  defp do_activate_case(
         %Schema.Case{state: :created} = case_schema,
         %State{} = state
       ) do
    case_table = get_table(:case, state)

    case_schema = %{
      case_schema
      | state: :active
    }

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

  defp do_activate_case(_case_schema, %State{} = _state) do
    {:error, :case_not_available}
  end

  defp persist_token(token_params, %State{} = state, options) do
    token_table = get_table(:token, state)
    workflow_id = Keyword.fetch!(options, :workflow_id)
    case_id = Keyword.fetch!(options, :case_id)
    place_id = Keyword.fetch!(options, :place_id)
    produced_by_task_id = Keyword.fetch!(options, :produced_by_task_id)

    token_schema =
      struct(
        Schema.Token,
        token_params
        |> Map.from_struct()
        |> Map.put(:id, make_id())
        |> Map.put(:workflow_id, workflow_id)
        |> Map.put(:case_id, case_id)
        |> Map.put(:place_id, place_id)
        |> Map.put(:produced_by_task_id, produced_by_task_id)
      )

    :ets.insert(
      token_table,
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

    {:ok, token_schema}
  end

  defp do_lock_token(
         %{state: :locked, locked_by_task_id: task_id} = token_schema,
         %{id: task_id},
         _state
       ) do
    {:ok, token_schema}
  end

  defp do_lock_token(%{state: :free} = token_schema, task_schema, %State{} = state) do
    token_schema = %{
      token_schema
      | state: :locked,
        locked_by_task_id: task_schema.id
    }

    token_table =
      :token
      |> get_table(state)

    true =
      :ets.update_element(
        token_table,
        token_schema.id,
        [
          {2, token_schema},
          {3,
           {
             token_schema.workflow_id,
             token_schema.case_id,
             token_schema.place_id,
             token_schema.produced_by_task_id,
             token_schema.locked_by_task_id,
             token_schema.state
           }}
        ]
      )

    {:ok, :token_schema}
  end

  defp do_lock_token(_token_params, _task_schema, %State{} = _state) do
    {:error, :token_not_available}
  end

  defp do_consume_token(
         %Schema.Token{locked_by_task_id: task_id, state: :locked} = token_schema,
         task_id,
         %State{} = state
       ) do
    token_schema = %{token_schema | consumed_by_task_id: task_id}

    true =
      :token
      |> get_table(state)
      |> :ets.update_element(
        token_schema.id,
        [
          {2, token_schema},
          {3,
           {
             token_schema.workflow_id,
             token_schema.case_id,
             token_schema.place_id,
             token_schema.produced_by_task_id,
             token_schema.locked_by_task_id,
             token_schema.state
           }}
        ]
      )

    {:ok, token_schema}
  end

  defp do_consume_token(_token_schema, _task_id, %State{}) do
    {:error, :token_not_available}
  end

  defp find_token(token_id, %State{} = state) do
    :token
    |> get_table(state)
    |> :ets.select([{{token_id, :"$1", :_}, [], [:"$1"]}])
    |> case do
      [token_schema] -> {:ok, token_schema}
      _ -> {:error, :token_not_found}
    end
  end

  defp find_tokens(case_id, token_states, %State{} = state) do
    tokens =
      :token
      |> get_table(state)
      |> :ets.select([{{:_, :"$1", {:_, case_id, :_, :_}}, [], ["$1"]}])
      |> Enum.filter(fn %{state: state} ->
        Enum.member?(token_states, state)
      end)

    {:ok, tokens}
  end

  defp persist_task(task_params, %State{} = state, options) do
    task_table = get_table(:task, state)
    workflow_id = Keyword.fetch!(options, :workflow_id)
    transition_id = Keyword.fetch!(options, :transition_id)
    case_id = Keyword.fetch!(options, :case_id)

    task_schema =
      struct(
        Schema.Task,
        task_params
        |> Map.from_struct()
        |> Map.put(:id, make_id())
        |> Map.put(:workflow_id, workflow_id)
        |> Map.put(:transition_id, transition_id)
        |> Map.put(:case_id, case_id)
      )

    :ets.insert(
      task_table,
      {
        task_schema.id,
        task_schema,
        {
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

  defp do_complete_task(
         %Schema.Task{state: :completed} = task_schema,
         _token_payload,
         %State{}
       ) do
    {:ok, task_schema}
  end

  defp do_complete_task(
         %Schema.Task{state: :started} = task_schema,
         token_payload,
         %State{} = state
       ) do
    task_schema = %{
      task_schema
      | state: :completed,
        token_payload: token_payload
    }

    true =
      :task
      |> get_table(state)
      |> :ets.update_element(
        task_schema.id,
        [
          {2, task_schema},
          {3,
           {
             task_schema.workflow_id,
             task_schema.transition_id,
             task_schema.case_id
           }}
        ]
      )

    {:ok, task_schema}
  end

  defp find_task(task_id, %State{} = state) do
    :task
    |> get_table(state)
    |> :ets.select([{{task_id, :"$1", :_}, [], [:"$1"]}])
    |> case do
      [task_schema] -> {:ok, task_schema}
      _ -> {:error, :task_not_found}
    end
  end

  defp find_task_by(case_id, transition_id, %State{} = state) do
    :task
    |> get_table(state)
    |> :ets.select([{{:_, :"$1", {:_, transition_id, case_id}}, [], [:"$1"]}])
    |> case do
      [task_schema] -> {:ok, task_schema}
      _ -> {:error, :task_not_found}
    end
  end

  defp persist_workitem(workitem_params, %State{} = state, options) do
    workitem_table = get_table(:workitem, state)
    workflow_id = Keyword.fetch!(options, :workflow_id)
    case_id = Keyword.fetch!(options, :case_id)
    task_id = Keyword.fetch!(options, :task_id)

    workitem_schema =
      struct(
        Schema.Workitem,
        workitem_params
        |> Map.from_struct()
        |> Map.put(:id, make_id())
        |> Map.put(:workflow_id, workflow_id)
        |> Map.put(:case_id, case_id)
        |> Map.put(:task_id, task_id)
      )

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

  defp do_start_workitem(
         %Schema.Workitem{state: :started} = workitem_schema,
         %State{} = _state
       ) do
    {:ok, workitem_schema}
  end

  defp do_start_workitem(
         %Schema.Workitem{state: :created} = workitem_schema,
         %State{} = state
       ) do
    workitem_table = get_table(:workitem, state)

    workitem_schema = %{
      workitem_schema
      | state: :started
    }

    true =
      :ets.update_element(
        workitem_table,
        workitem_schema.id,
        [{2, workitem_schema}]
      )

    {:ok, workitem_schema}
  end

  defp do_start_workitem(_workitem_schema, %State{} = _state) do
    {:error, :workitem_not_available}
  end

  defp do_complete_workitem(
         %Schema.Workitem{state: :completed} = workitem_schema,
         _workitem_output,
         %State{} = _state
       ) do
    {:ok, workitem_schema}
  end

  defp do_complete_workitem(
         %Schema.Workitem{state: workitem_state} = workitem_schema,
         workitem_output,
         %State{} = state
       )
       when workitem_state in [:created, :started] do
    workitem_table = get_table(:workitem, state)

    workitem_schema = %{
      workitem_schema
      | state: :completed,
        output: workitem_output
    }

    true =
      :ets.update_element(
        workitem_table,
        workitem_schema.id,
        [{2, workitem_schema}]
      )

    {:ok, workitem_schema}
  end

  defp do_complete_workitem(_workitem_schema, _workitem_output, %State{} = _state) do
    {:error, :workitem_not_available}
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

  defp get_table(table_type, %State{} = state) do
    table_name = String.to_existing_atom("#{table_type}_table")
    Map.fetch!(state, table_name)
  end

  defp storage_name(adapter_meta) when is_map(adapter_meta),
    do: Map.get(adapter_meta, :name)

  defp make_id, do: :erlang.unique_integer()

  defp reversed_arc_direction(:in), do: :out
  defp reversed_arc_direction(:out), do: :in
end
