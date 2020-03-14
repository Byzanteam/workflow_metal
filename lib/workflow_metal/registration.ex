defmodule WorkflowMetal.Registration do
  @moduledoc """
  Use the process registry configured for a WorkflowMetal application.
  """

  @type application :: WorkflowMetal.Application.t()
  @type config :: keyword

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
end
