defmodule WorkflowMetal.Storage do
  @moduledoc false

  use GenServer

  @type application() :: WorkflowMetal.Application.t()
  @type opts() :: [name: term(), init: {key :: term(), value :: term()}]

  @doc false
  @spec start_link(application(), opts()) :: GenServer.on_start()
  def start_link(_application, opts) do
    name = Keyword.fetch!(opts, :name)
    init = Keyword.fetch!(opts, :init)
    GenServer.start_link(__MODULE__, [init: init], name: name)
  end

  @impl true
  def init(init: init) do
    table = :ets.new(:storage, [:set, :private])
    :ets.insert(table, init)

    {:ok, table}
  end

  @doc false
  def via_name(application, workflow_id) do
    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end
end
