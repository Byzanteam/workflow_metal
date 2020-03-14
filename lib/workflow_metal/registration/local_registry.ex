defmodule WorkflowMetal.Registration.LocalRegistry do
  @moduledoc """
  Local process registration, restricted to a single node, using Elixir's
  `Registry` module.
  """

  require Logger

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

  defp registry_name(adapter_meta), do: Map.fetch!(adapter_meta, :registry_name)
end
