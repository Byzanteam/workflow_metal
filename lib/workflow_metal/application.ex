defmodule WorkflowMetal.Application do
  @moduledoc false

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @opts opts

      @doc """
      Start a workflow_metal application
      """
      @spec start() :: {:ok, pid()}
      def start do
        name = name(@opts)

        WorkflowMetal.Application.Supervisor.start_link(__MODULE__, name, @opts)
      end

      defp name(opts) do
        case Keyword.get(opts, :name) do
          nil ->
            __MODULE__

          name when is_atom(name) ->
            name

          invalid ->
            raise ArgumentError,
              message:
                "expected :name option to be an atom but got: " <>
                  inspect(invalid)
        end
      end
    end
  end
end
