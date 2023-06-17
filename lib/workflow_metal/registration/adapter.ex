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

  @type child_spec :: module | {module, term}
  @type on_start_child :: {:ok, pid} | {:error, term}

  @doc """
  Return a supervisor spec for the registry
  """
  @callback child_spec(application, config) ::
              {:ok, :supervisor.child_spec() | {module, term} | module | nil, adapter_meta}

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name
  """
  @callback via_tuple(adapter_meta :: adapter_meta, name :: term) :: {:via, module, term}

  @doc """
  Start a child under a DynamicSupervisor. If a child with give name already
  exists, find its pid.
  """
  @callback start_child(
              adapter_meta :: adapter_meta,
              name :: term,
              supervisor :: Supervisor.supervisor(),
              child_spec :: child_spec()
            ) :: on_start_child

  @doc """
  Get the pid of a registered name.

  Returns `:undefined` if the name is unregistered.
  """
  @callback whereis_name(adapter_meta, name :: term()) :: pid() | :undefined
end
