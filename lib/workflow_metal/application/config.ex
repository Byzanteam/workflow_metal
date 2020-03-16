defmodule WorkflowMetal.Application.Config do
  @moduledoc false

  @type t :: map()
  @type application :: WorkflowMetal.Application.t()

  @doc false
  @spec start_link(application, t) :: Agent.on_start()
  def start_link(application, initial_value) do
    Agent.start_link(fn -> initial_value end, name: config_name(application))
  end

  @doc """
  Store settings of an application.
  """
  @spec set(application, atom, term) :: :ok
  def set(application, key, value) when is_atom(application) do
    Agent.update(config_name(application), fn state ->
      Keyword.put(state, key, value)
    end)
  end

  @doc """
  Retrive settings of an application.
  """
  @spec get(application, atom) :: term
  def get(application, key) when is_atom(application) and is_atom(key) do
    Agent.get(config_name(application), fn state ->
      Keyword.get(state, key)
    end)
  end

  defp config_name(application) do
    Module.concat(application, Config)
  end
end
