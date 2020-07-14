defmodule WorkflowMetal.Registration.LocalRegistry do
  @moduledoc """
  Local process registration, restricted to a single node, using Elixir's
  `Registry` module.
  """

  @behaviour WorkflowMetal.Registration.Adapter

  @doc """
  Return a supervisor spec for the registry.
  """
  @impl WorkflowMetal.Registration.Adapter
  def child_spec(application, _config) do
    registry_name = Module.concat(application, LocalRegistry)

    child_spec = {Registry, keys: :unique, name: registry_name}

    {:ok, child_spec, %{registry_name: registry_name}}
  end

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name.
  """
  @impl WorkflowMetal.Registration.Adapter
  def via_tuple(adapter_meta, name) do
    registry_name = registry_name(adapter_meta)

    {:via, Registry, {registry_name, name}}
  end

  @doc false
  @impl WorkflowMetal.Registration.Adapter
  def start_child(adapter_meta, name, supervisor, child_spec) do
    name = via_tuple(adapter_meta, name)

    child_spec =
      case child_spec do
        module when is_atom(module) ->
          {module, name: name}

        {module, args} when is_atom(module) and is_list(args) ->
          {module, Keyword.put(args, :name, name)}
      end

    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      reply -> reply
    end
  end

  @doc false
  @impl WorkflowMetal.Registration.Adapter
  def whereis_name(adapter_meta, name) do
    registry_name = registry_name(adapter_meta)

    Registry.whereis_name({registry_name, name})
  end

  defp registry_name(adapter_meta), do: Map.fetch!(adapter_meta, :registry_name)
end
