defmodule WorkflowMetal.Application do
  @moduledoc false

  alias WorkflowMetal.Application.Config

  @type t() :: module()
  @type application_config :: keyword()
  @type application_meta :: {t, application_config}

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
          application(),
          config()
        )
      end

      @doc """
      Retrive the supervisor name of the current application.
      """
      def application do
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

  @doc false
  @spec registry_adapter(t) :: {module, map}
  def registry_adapter(application), do: Config.get(application, :registry)
end
