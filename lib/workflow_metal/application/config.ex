defmodule WorkflowMetal.Application.Config do
  @moduledoc false

  @type t() :: map()
  @type application() :: WorkflowMetal.Application.t()

  @typep key() :: atom()
  @typep value() :: term()
  # credo:disable-for-previous-line JetCredo.Checks.ExplicitAnyType

  @doc false
  @spec start_link(application(), t()) :: Agent.on_start()
  def start_link(application, initial_value) do
    Agent.start_link(fn -> initial_value end, name: config_name(application))
  end

  @doc """
  Store settings of an application.
  """
  @spec set(application(), key(), value()) :: :ok
  def set(application, key, value) when is_atom(application) do
    Agent.update(config_name(application), fn state ->
      Keyword.put(state, key, value)
    end)
  end

  @doc """
  Retrieve settings of an application.
  """
  @spec get(application(), key()) :: value()
  def get(application, key) when is_atom(application) and is_atom(key) do
    Agent.get(config_name(application), fn state ->
      Keyword.get(state, key)
    end)
  end

  @doc """
  Retrieves the compile time configuration.
  """
  @spec compile_config(application(), Keyword.t()) :: Keyword.t()
  def compile_config(_application, config) do
    Keyword.take(config, [:name, :registry, :storage])
  end

  defp config_name(application) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(application, Config)
  end
end
