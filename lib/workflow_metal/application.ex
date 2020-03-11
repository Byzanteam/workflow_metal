defmodule WorkflowMetal.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @doc false
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: WorkflowMetal.Worker.start_link(arg)
      # {WorkflowMetal.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WorkflowMetal.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
