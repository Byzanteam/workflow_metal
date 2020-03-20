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
      workflows: %{}
    ]
  end

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
  def upsert_workflow(adapter_meta, workflow_id, workflow_version, workflow_data) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:upsert, workflow_id, workflow_version, workflow_data})
  end

  @impl WorkflowMetal.Storage.Adapter
  def retrive_workflow(adapter_meta, workflow_id, workflow_version) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:retrive, workflow_id, workflow_version})
  end

  @impl WorkflowMetal.Storage.Adapter
  def delete_workflow(adapter_meta, workflow_id, workflow_version) do
    storage = storage_name(adapter_meta)

    GenServer.call(storage, {:delete, workflow_id, workflow_version})
  end

  @impl GenServer
  def handle_call(
        {:upsert, workflow_id, workflow_version, workflow_data},
        _from,
        %State{} = state
      ) do
    {reply, state} = persist_workflow({workflow_id, workflow_version, workflow_data}, state)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:retrive, workflow_id, workflow_version},
        _from,
        %State{} = state
      ) do
    %State{workflows: workflows} = state

    version = to_string(workflow_version)

    reply =
      case Map.get(workflows, workflow_id, nil) do
        %{^version => workflow_data} -> {:ok, workflow_data}
        %{} -> {:error, :workflow_version_not_found}
        nil -> {:error, :workflow_not_found}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(
        {:delete, workflow_id, workflow_version},
        _from,
        %State{} = state
      ) do
    %State{workflows: workflows} = state

    workflow =
      workflows
      |> Map.get(workflow_id, %{})
      |> Map.delete(to_string(workflow_version))

    {:reply, :ok, %{state | workflows: Map.put(workflows, workflow_id, workflow)}}
  end

  defp persist_workflow({workflow_id, workflow_version, workflow_data}, %State{} = state) do
    %{workflows: workflows} = state

    workflow =
      workflows
      |> Map.get(workflow_id, %{})
      |> Map.put(to_string(workflow_version), workflow_data)

    {:ok, %{state | workflows: Map.put(workflows, workflow_id, workflow)}}
  end

  defp storage_name(adapter_meta) when is_map(adapter_meta),
    do: Map.get(adapter_meta, :name)
end
