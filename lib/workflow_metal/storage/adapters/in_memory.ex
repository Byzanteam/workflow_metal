defmodule WorkflowMetal.Storage.Adapters.InMemory do
  @moduledoc """
  An in-memory storage adapter useful for testing as no persistence provided.
  """

  @behaviour WorkflowMetal.Storage.Adapter

  use GenServer

  defmodule State do
    @moduledoc false

    defstruct [
      :name,
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
    {:ok, state}
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
  def create_workflow(adapter_meta, workflow_schema) do
    storage = storage_name(adapter_meta)
    %{id: workflow_id} = workflow_schema

    GenServer.call(storage, {:create_workflow, workflow_id, workflow_schema})
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
  def fetch_tokens(adapter_meta, workflow_id, case_id, token_states) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:fetch_tokens, workflow_id, case_id, token_states})
  end

  @impl GenServer
  def handle_call(
        {:create_workflow, workflow_id, workflow_schema},
        _from,
        %State{} = state
      ) do
    %{workflows: workflows} = state

    if Map.has_key?(workflows, workflow_id) do
      {:reply, {:error, :duplicate_workflow}, state}
    else
      {reply, state} = persist_workflow({workflow_id, workflow_schema}, state)

      {:reply, reply, state}
    end
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

  defp persist_workflow({workflow_id, workflow_schema}, %State{} = state) do
    %{workflows: workflows} = state

    {:ok, %{state | workflows: Map.put(workflows, workflow_id, workflow_schema)}}
  end

  defp persist_case({case_key, case_schema}, %State{} = state) do
    %{cases: cases} = state

    {:ok, %{state | cases: Map.put(cases, case_key, case_schema)}}
  end

  defp storage_name(adapter_meta) when is_map(adapter_meta),
    do: Map.get(adapter_meta, :name)
end
