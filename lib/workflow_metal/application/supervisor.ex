defmodule WorkflowMetal.Application.Supervisor do
  @moduledoc false

  use Supervisor

  @type application :: WorkflowMetal.Application.t()
  @type config :: keyword

  @doc """
  Start the application supervisor.
  """
  @spec start_link(application, config) :: Supervisor.on_start()
  def start_link(application, config) do
    Supervisor.start_link(
      __MODULE__,
      {application, config},
      name: application
    )
  end

  @impl true
  def init({application, config}) do
    {registry_child_spec, config} = registry_child_spec(application, config)
    {storage_child_spec, config} = storage_child_spec(application, config)

    config_child_spec = config_child_spec(application, config)

    children = [
      config_child_spec,
      registry_child_spec,
      storage_child_spec,
      {WorkflowMetal.Application.WorkflowsSupervisor, application}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp config_child_spec(application, config) do
    %{
      id: WorkflowMetal.Application.Config,
      start: {WorkflowMetal.Application.Config, :start_link, [application, config]}
    }
  end

  defp registry_child_spec(application, config) do
    {adapter, adapter_config} = WorkflowMetal.Registration.adapter(application, config)

    {:ok, child_spec, adapter_meta} = adapter.child_spec(application, adapter_config)

    config = Keyword.put(config, :registry, {adapter, adapter_meta})

    {child_spec, config}
  end

  defp storage_child_spec(application, config) do
    {adapter, adapter_config} = WorkflowMetal.Storage.adapter(application, config)

    {:ok, child_spec, adapter_meta} = adapter.child_spec(application, adapter_config)

    config = Keyword.put(config, :storage, {adapter, adapter_meta})

    {child_spec, config}
  end

  @doc """
  Retrieves the compile time configuration.
  """
  def compile_config(_application, config) do
    Keyword.take(config, [:name, :registry, :storage])
  end
end
