defmodule WorkflowMetal.Application do
  @moduledoc false

  alias WorkflowMetal.Application.Config

  @type t() :: module()
  @type application_config :: keyword()
  @type application_meta :: {t, application_config}

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      alias WorkflowMetal.Application.WorkflowsSupervisor

      @config WorkflowMetal.Application.Config.compile_config(__MODULE__, opts)

      def child_spec(_opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, []},
          type: :supervisor
        }
      end

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

      # API

      @doc """
      Create a workflow, store it in the storage
      """
      def create_workflow(workflow_schema) do
        WorkflowsSupervisor.create_workflow(
          application(),
          workflow_schema
        )
      end

      @doc """
      Open a workflow
      """
      def open_workflow(workflow_id) do
        WorkflowsSupervisor.open_workflow(
          application(),
          workflow_id
        )
      end

      @doc """
      Lock tokens of a task.

      This usually happens before execute the workitem.
      """
      def lock_tokens(task_id) do
        WorkflowMetal.Task.Supervisor.lock_tokens(
          application(),
          task_id
        )
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

  @doc false
  @spec storage_adapter(t) :: {module, map}
  def storage_adapter(application), do: Config.get(application, :storage)
end
