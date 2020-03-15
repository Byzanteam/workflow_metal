defmodule WorkflowMetal.Registration.Adapter do
  @moduledoc """
  Defines a behaviour for a process registry to be used by WorkflowMetal.

  By default, WorkflowMetal will use a local process registry, defined in
  `WorkflowMetal.Registration.LocalRegistry`, that uses Elixir's `Registry` module
  for local process registration. This limits WorkflowMetal to only run on a single
  node. However the `WorkflowMetal.Registration` behaviour can be implemented by a
  library to provide distributed process registration to support running on a
  cluster of nodes.
  """

  @type adapter_meta :: map
  @type application :: WorkflowMetal.Application.t()
  @type config :: keyword

  @doc """
  Return a supervisor spec for the registry
  """
  @callback child_spec(application, config) ::
              {:ok, Supervisor.child_spec(), adapter_meta}

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name
  """
  @callback via_tuple(adapter_meta :: adapter_meta, name :: term) :: {:via, module, term}
end
