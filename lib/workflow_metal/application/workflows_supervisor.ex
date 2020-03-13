defmodule WorkflowMetal.Application.WorkflowsSupervisor do
  @moduledoc """
  Supervise all workflows.
  """

  use DynamicSupervisor

  @doc """
  Start the workflows supervisor to supervise all workflows.
  """
  @spec start_link({module(), atom(), keyword()}) :: Supervisor.on_start()
  def start_link({_application, name, _opts} = args) do
    supervisor_name = supervisor_name(name)

    DynamicSupervisor.start_link(
      __MODULE__,
      args,
      name: supervisor_name
    )
  end

  @impl true
  def init(args) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [args])
  end
end
