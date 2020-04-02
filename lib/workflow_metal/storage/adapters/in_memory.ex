defmodule WorkflowMetal.Storage.Adapters.InMemory do
  @moduledoc """
  An in-memory storage adapter useful for testing as no persistence provided.
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
      :task_table,
      :token_table,
      workflows: %{},
      cases: %{}
    ]
  end

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
          token_table: :ets.new(:token_table, [:set, :private])
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
  def fetch_places(adapter_meta, transition_id, arc_direction) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_places, transition_id, arc_direction})
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
  def create_task(adapter_meta, task_params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:create_task, task_params})
  end

  # TODO: issue genesis token
  @impl WorkflowMetal.Storage.Adapter
  def issue_token(adapter_meta, token_params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:issue_token, token_params})
  end

  @impl WorkflowMetal.Storage.Adapter
  def create_workitem(adapter_meta, workitem_params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:create_workitem, workitem_params})
  end

  @impl WorkflowMetal.Storage.Adapter
  def update_workitem(adapter_meta, workitem_schema) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:update_workitem, workitem_schema})
  end

  @doc """
  Reset state.
  """
  def reset!(application) do
    {_adapter, adapter_meta} = WorkflowMetal.Application.storage_adapter(application)
    storage = storage_name(adapter_meta)

    GenServer.call(storage, :reset!)
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
        {:ok, produced_by_task} <- find_task(produced_by_task_id, state)
      ) do
        persist_token(
          token_params,
          state,
          workflow_id: workflow_schema.id,
          case_id: case_schema.id,
          place_id: place_schema.id,
          produced_by_task_id: produced_by_task.id
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
        {:create_workitem, workitem_params},
        _from,
        %State{} = state
      ) do
    %State{workflows: workflows, cases: cases} = state

    %{
      workflow_id: workflow_id,
      case_id: case_id
    } = workitem_params

    with(
      {:workflow, workflow_schema} when not is_nil(workflow_schema) <-
        {:workflow, Map.get(workflows, workflow_id)},
      {:case, case_schema} when not is_nil(case_schema) <-
        {:case, Map.get(cases, {workflow_id, case_id})}
    ) do
      # TODO: fetch task and put transition_id
      workitem_schema =
        Schema.Workitem
        |> struct(Map.from_struct(workitem_params))
        |> Map.put(:id, make_ref())

      %{workitems: workitems} = case_schema
      workitems = [workitem_schema | workitems || []]

      cases = Map.put(cases, {workflow_id, case_id}, %{case_schema | workitems: workitems})

      {:reply, {:ok, workitem_schema}, %{state | cases: cases}}
    else
      {:workflow, nil} -> {:reply, {:error, :workflow_not_found}, state}
      {:case, nil} -> {:reply, {:error, :case_not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(
        {:update_workitem, workitem_schema},
        _from,
        %State{} = state
      ) do
    %State{workflows: workflows, cases: cases} = state

    %{
      workflow_id: workflow_id,
      case_id: case_id
    } = workitem_schema

    reply =
      with(
        {:workflow, workflow_schema} when not is_nil(workflow_schema) <-
          {:workflow, Map.get(workflows, workflow_id)},
        {:case, case_schema} when not is_nil(case_schema) <-
          {:case, Map.get(cases, {workflow_id, case_id})}
      ) do
        case case_schema do
          %{workitems: [_ | _] = workitems} ->
            case Enum.find_index(workitems, &(&1.id === workitem_schema.id)) do
              nil ->
                {:reply, {:error, :workitem_not_found}, state}

              index ->
                workitems = List.replace_at(workitems, index, workitem_schema)

                cases =
                  Map.put(cases, {workflow_id, case_id}, %{case_schema | workitems: workitems})

                {:reply, workitem_schema, %{state | cases: cases}}
            end
        end
      else
        {:workflow, nil} ->
          {:reply, {:error, :workflow_not_found}, state}

        {:case, nil} ->
          {:reply, {:error, :case_not_found}, state}
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
          token_schema.produced_by_task_id
        }
      }
    )

    {:ok, token_schema}
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

  defp find_task(task_id, %State{} = state) do
    :task
    |> get_table(state)
    |> :ets.select([{{task_id, :"$1", :_}, [], [:"$1"]}])
    |> case do
      [task_schema] -> {:ok, task_schema}
      _ -> {:error, :task_not_found}
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
