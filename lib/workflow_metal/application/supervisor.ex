defmodule WorkflowMetal.Application.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  @type application :: WorkflowMetal.Application.t()
  @type config :: keyword

  @doc """
  Start the application supervisor.
  """
  @spec start_link(application, atom, config) :: Supervisor.on_start()
  def start_link(application, name, config) do
    Supervisor.start_link(
      __MODULE__,
      {application, name, config},
      name: name
    )
  end

  @impl true
  def init({application, name, config} = args) do
    {registry_child_spec, config} = registry_child_spec(name, config)

    children = [
      registry_child_spec,
      {WorkflowMetal.Application.WorkflowsSupervisor, {application, name, config}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp registry_child_spec(name, config) do
    {adapter, adapter_config} = WorkflowMetal.Registration.adapter(name, config)

    {:ok, child_spec, adapter_meta} = adapter.child_spec(name, adapter_config)

    config = Keyword.put(config, :registry, {adapter, adapter_meta})

    {child_spec, config}
  end

  @doc """
  Retrieves the compile time configuration.
  """
  def compile_config(_application, config) do
    Keyword.take(config, [:name])
  end
end
