defmodule WorkflowMetal.Application do
  @moduledoc """
  A workflow_metal application is a collection of workflows, cases, tasks and workitems.

  In `config/config.exs` set default_lifespan_timeout for any `Case`, `Task` and `Workitem`:

      config :my_app, MyApp.Application,
        case: [
          lifespan_timeout: 30000
        ],
        task: [
          lifespan_timeout: 60000
        ],
        workitem: [
          lifespan_timeout: 300000
        ]
  """

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
      Retrieve the supervisor name of the current application.
      """
      def application do
        name(config())
      end

      @doc """
      Retrieve the config of the current application.
      """
      def config do
        @config
      end

      # API

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
      Open a case('GenServer')
      """
      def open_case(case_id) do
        WorkflowMetal.Case.Supervisor.open_case(application(), case_id)
      end

      @doc """
      Terminate a case('GenServer')
      """
      def terminate_case(case_id) do
        WorkflowMetal.Case.Supervisor.terminate_case(application(), case_id)
      end

      @doc """
      Pre-execute a task that the workitem belongs to.

      Lock tokens before a workitem execution.
      """
      @spec preexecute(workitem_id :: WorkflowMetal.Workitem.Workitem.id()) ::
              WorkflowMetal.Task.Task.on_preexecute()
      def preexecute(workitem_id) do
        WorkflowMetal.Workitem.Supervisor.preexecute(
          application(),
          workitem_id
        )
      end

      @doc """
      Complete a workitem
      """
      @spec complete_workitem(
              workitem_id :: WorkflowMetal.Workitem.Workitem.id(),
              output :: WorkflowMetal.Workitem.Workitem.output()
            ) ::
              WorkflowMetal.Workitem.Workitem.on_complete()
      def complete_workitem(workitem_id, output) do
        WorkflowMetal.Workitem.Supervisor.complete_workitem(
          application(),
          workitem_id,
          output
        )
      end

      @doc """
      Abandon a workitem.
      """
      @spec abandon_workitem(workitem_id :: WorkflowMetal.Workitem.Workitem.id()) ::
              WorkflowMetal.Workitem.Workitem.on_abandon()
      def abandon_workitem(workitem_id) do
        WorkflowMetal.Workitem.Supervisor.abandon_workitem(
          application(),
          workitem_id
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
