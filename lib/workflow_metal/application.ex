defmodule WorkflowMetal.Application do
  @moduledoc false

  @type application() :: module()

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @config WorkflowMetal.Application.Supervisor.compile_config(__MODULE__, opts)

      @doc """
      Start a workflow_metal application
      """
      @spec start_link() :: Supervisor.on_start()
      def start_link do
        WorkflowMetal.Application.Supervisor.start_link(
          __MODULE__,
          supervisor_name(),
          config()
        )
      end

      @doc """
      Retrive the supervisor name of the current application.
      """
      def supervisor_name do
        name(config())
      end

      @doc """
      Retrive the config of the current application.
      """
      def config do
        @config
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
