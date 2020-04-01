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
          arc_table: :ets.new(:arc_table, [:set, :private])
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

    GenServer.call(storage, {:delete, workflow_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def create_case(adapter_meta, case_schema) do
    storage = storage_name(adapter_meta)
    %{workflow_id: workflow_id, id: case_id} = case_schema

    GenServer.call(storage, {:create_case, workflow_id, case_id, case_schema})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_case(adapter_meta, workflow_id, case_id) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_case, workflow_id, case_id})
  end

  @impl WorkflowMetal.Storage.Adapter
  def create_token(adapter_meta, token_params) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:create_token, token_params})
  end

  @impl WorkflowMetal.Storage.Adapter
  def fetch_tokens(adapter_meta, workflow_id, case_id, token_states) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_tokens, workflow_id, case_id, token_states})
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
    %State{workflows: workflows} = state

    reply =
      case Map.get(workflows, workflow_id, nil) do
        nil -> {:error, :workflow_not_found}
        workflow_schema -> {:ok, workflow_schema}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:delete, workflow_id},
        _from,
        %State{} = state
      ) do
    %State{workflows: workflows} = state

    {:reply, :ok, %{state | workflows: Map.delete(workflows, workflow_id)}}
  end

  @impl GenServer
  def handle_call(
        {:create_case, workflow_id, case_id, workflow_schema},
        _from,
        %State{} = state
      ) do
    %{workflows: workflows, cases: cases} = state

    case Map.get(workflows, workflow_id) do
      nil ->
        {:reply, {:error, :workflow_not_found}, state}

      _ ->
        case_key = {workflow_id, case_id}

        if Map.has_key?(cases, case_key) do
          {:reply, {:error, :duplicate_case}, state}
        else
          {reply, state} = persist_case({case_key, workflow_schema}, state)

          {:reply, reply, state}
        end
    end
  end

  @impl GenServer
  def handle_call(
        {:fetch_case, workflow_id, case_id},
        _from,
        %State{} = state
      ) do
    %State{workflows: workflows, cases: cases} = state

    reply =
      case Map.get(workflows, workflow_id) do
        nil ->
          {:error, :workflow_not_found}

        _ ->
          case Map.get(cases, {workflow_id, case_id}) do
            nil -> {:error, :case_not_found}
            case_schema -> {:ok, case_schema}
          end
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:create_token, token_params},
        _from,
        %State{} = state
      ) do
    %State{workflows: workflows, cases: cases} = state

    %{
      workflow_id: workflow_id,
      case_id: case_id
    } = token_params

    reply =
      with(
        {:workflow, workflow_schema} when not is_nil(workflow_schema) <-
          {:workflow, Map.get(workflows, workflow_id)},
        {:case, case_schema} when not is_nil(case_schema) <-
          {:case, Map.get(cases, {workflow_id, case_id})}
      ) do
        token_schema =
          Schema.Token
          |> struct(Map.from_struct(token_params))
          # TODO: use uuid
          |> Map.put(:id, make_ref())

        %{tokens: tokens} = case_schema
        tokens = [token_schema | tokens || []]

        {:ok, %{case_schema | tokens: tokens}}
      else
        {:workflow, nil} -> {:error, :workflow_not_found}
        {:case, nil} -> {:error, :case_not_found}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:fetch_tokens, workflow_id, case_id, token_states},
        _from,
        %State{} = state
      ) do
    %State{workflows: workflows, cases: cases} = state

    reply =
      with(
        {:workflow, workflow_schema} when not is_nil(workflow_schema) <-
          {:workflow, Map.get(workflows, workflow_id)},
        {:case, case_schema} when not is_nil(case_schema) <-
          {:case, Map.get(cases, {workflow_id, case_id})}
      ) do
        case {token_states, case_schema} do
          {:all, %{tokens: tokens}} ->
            {:ok, List.wrap(tokens)}

          {token_states, %{tokens: [_ | _] = tokens}} ->
            filter_func = fn token ->
              Enum.member?(token_states, token.state)
            end

            {:ok, Enum.filter(tokens, filter_func)}

          _ ->
            # match on tokens is `nil`
            {:ok, []}
        end
      else
        {:workflow, nil} -> {:error, :workflow_not_found}
        {:case, nil} -> {:error, :case_not_found}
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

  defp persist_workflow(workflow_params, %State{} = state) do
    workflow_table = get_table(:workflow, state)

    workflow_schema =
      struct(
        Schema.Workflow,
        workflow_params |> Map.from_struct() |> Map.put(:id, make_id())
      )

    :ets.insert(workflow_table, {workflow_schema.id, workflow_schema})

    persist_places(
      Map.get(workflow_params, :places),
      state,
      workflow_id: workflow_schema.id
    )

    persist_transitions(
      Map.get(workflow_params, :transitions),
      state,
      workflow_id: workflow_schema.id
    )

    persist_arcs(
      Map.get(workflow_params, :arcs),
      state,
      workflow_id: workflow_schema.id
    )

    {:ok, workflow_schema}
  end

  defp persist_place(place_params, %State{} = state) do
    place_table = get_table(:place, state)

    place_schema =
      struct(
        Schema.Place,
        place_params |> Map.from_struct() |> Map.put(:id, make_id())
      )

    :ets.insert(
      place_table,
      {
        place_schema.id,
        place_schema,
        place_schema.type,
        place_schema.workflow_id
      }
    )

    {:ok, place_schema}
  end

  defp persist_places(places_params, %State{} = state, options) do
    workflow_id = Keyword.fetch!(options, :workflow_id)

    Enum.map(places_params, fn place_params ->
      {:ok, place_schema} =
        place_params
        |> Map.put(:workflow_id, workflow_id)
        |> persist_place(state)

      place_schema
    end)
  end

  defp persist_transition(transition_params, %State{} = state) do
    transition_table = get_table(:transition, state)

    transition_schema =
      struct(
        Schema.Transition,
        transition_params |> Map.from_struct() |> Map.put(:id, make_id())
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

  defp persist_transitions(transitions_params, %State{} = state, options) do
    workflow_id = Keyword.fetch!(options, :workflow_id)

    Enum.map(transitions_params, fn transition_params ->
      {:ok, transition_schema} =
        transition_params
        |> Map.put(:workflow_id, workflow_id)
        |> persist_transition(state)

      transition_schema
    end)
  end

  defp persist_arc(arc_params, %State{} = state) do
    arc_table = get_table(:arc, state)

    arc_schema =
      struct(
        Schema.Arc,
        arc_params |> Map.from_struct() |> Map.put(:id, make_id())
      )

    :ets.insert(
      arc_table,
      {
        arc_schema.id,
        arc_schema,
        {arc_schema.place_id, arc_schema.transition_id, arc_schema.direction}
      }
    )

    {:ok, arc_schema}
  end

  defp persist_arcs(arcs_params, %State{} = state, options) do
    workflow_id = Keyword.fetch!(options, :workflow_id)

    Enum.map(arcs_params, fn arc_params ->
      {:ok, arc_schema} =
        arc_params
        |> Map.put(:workflow_id, workflow_id)
        |> persist_arc(state)

      arc_schema
    end)
  end

  defp persist_case({case_key, case_schema}, %State{} = state) do
    %{cases: cases} = state

    {:ok, %{state | cases: Map.put(cases, case_key, case_schema)}}
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

  defp get_table(table_type, %State{} = state) do
    table_name = String.to_existing_atom("#{table_type}_table")
    Map.fetch!(state, table_name)
  end

  defp storage_name(adapter_meta) when is_map(adapter_meta),
    do: Map.get(adapter_meta, :name)

  defp make_id, do: :erlang.unique_integer()
end
