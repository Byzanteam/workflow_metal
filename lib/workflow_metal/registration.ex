defmodule WorkflowMetal.Registration do
  @moduledoc """
  Use the process registry configured for a WorkflowMetal application.
  """

  alias WorkflowMetal.Registration.Adapter

  @type application :: WorkflowMetal.Application.t()
  @type config :: keyword

  @doc false
  def via_tuple(application, name) do
    {adapter, adapter_meta} = WorkflowMetal.Application.registry_adapter(application)

    adapter.via_tuple(adapter_meta, name)
  end

  @doc """
  Get the configured process registry.

  Defaults to a local registry, restricted to running on a single node.
  """
  @spec adapter(application, config) :: {module, config}
  def adapter(application, config) do
    case Keyword.get(config, :registry, :local) do
      :local ->
        {WorkflowMetal.Registration.LocalRegistry, []}

      adapter when is_atom(adapter) ->
        {adapter, []}

      config ->
        raise ArgumentError,
              "invalid :registry option for WorkflowMetal application `#{inspect(application)}`: `#{
                inspect(config)
              }`"
    end
  end

  @doc """
  """
  @spec start_child(application, term, Supervisor.supervisor(), Adapter.child_spec()) ::
          WorkflowMetal.Registration.Adapter.on_start_child()
  def start_child(application, name, supervisor, child_spec) do
    {adapter, adapter_meta} = WorkflowMetal.Application.registry_adapter(application)

    adapter.start_child(adapter_meta, name, supervisor, child_spec)
  end

  @doc """
  Get the pid of a registered name.

  Returns `:undefined` if the name is unregistered.
  """
  @spec whereis_name(application, term) :: pid() | :undefined
  def whereis_name(application, name) do
    {adapter, adapter_meta} = WorkflowMetal.Application.registry_adapter(application)

    adapter.whereis_name(adapter_meta, name)
  end
end
