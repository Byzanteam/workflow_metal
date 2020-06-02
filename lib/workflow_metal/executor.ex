defmodule WorkflowMetal.Executor do
  @moduledoc """
  Defines an executor module.

  The `WorkflowMetal.Executor` behaviour is used to define a transition.

  ## Supported return values

    - `:started` - the executor is started, and report its state latter, this is useful for long-running tasks(for example: timer).
    - `{:completed, workitem_output}` - the executor has been started and comploted already.
    - `{:failed, reason}` - the executor failed to execute.

  ## Example
      defmodule ExampleExecutor do
        use WorkflowMetal.Executor

        alias WorkflowMetal.Storage.Schema

        @impl WorkflowMetal.Executor
        def execute(%Schema.Workitem{}, options) do
          {:ok, _tokens} = preexecute(workitem, options)

          {:completed, {:output, :ok}}
        end
      end

      defmodule AsyncExampleExecutor do
        use WorkflowMetal.Executor

        alias WorkflowMetal.Storage.Schema

        @impl WorkflowMetal.Executor
        def execute(%Schema.Workitem{} = workitem, options) do
          {:ok, tokens} = preexecute(workitem, options)

          Task.async(__MODULE__, :run, [workitem, tokens, options])
          :started
        end

        def run(%Schema.Workitem{} = workitem, _tokens, _options) do
          WorkflowApplication.complete_workitem(workitem, {:output, :ok})
        end
      end
  """

  alias WorkflowMetal.Storage.Schema

  @type options :: [
          executor_params: Schema.Transition.executor_params(),
          application: WorkflowMetal.Application.t()
        ]

  @type workitem :: Schema.Workitem.t()
  @type token_payload :: Schema.Token.payload()
  @type workitem_output :: Schema.Workitem.output()

  @doc """
  Run an executor and return its state to the `workitem` process.
  """
  @callback execute(workitem, options) ::
              :started
              | {:completed, workitem_output}

  @doc """
  Merge outputs of all workitems.
  """
  @callback build_token_payload(nonempty_list(workitem), options) ::
              {:ok, token_payload}

  @doc false
  defmacro __using__(opts) do
    application = Keyword.get(opts, :application)

    quote do
      alias WorkflowMetal.Storage.Schema

      @application unquote(application)

      @behaviour WorkflowMetal.Executor

      @before_compile unquote(__MODULE__)

      @impl WorkflowMetal.Executor
      def build_token_payload(workitems, _options) do
        {
          :ok,
          workitems
          |> Enum.filter(&(&1.state === :completed))
          |> Enum.reduce(%{}, &Map.put(&2, &1.id, &1.output))
        }
      end

      defoverridable WorkflowMetal.Executor
    end
  end

  @doc false
  @spec __before_compile__(env :: Macro.Env.t()) :: Macro.t()
  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Lock tokens before a workitem execution.
      """
      @spec preexecute(
              application :: WorkflowMetal.Application.t(),
              workitem ::
                WorkflowMetal.Workitem.Workitem.t() | WorkflowMetal.Workitem.Workitem.id()
            ) :: WorkflowMetal.Task.Task.on_preexecute()
      def preexecute(application \\ @application, workitem) do
        application.preexecute(workitem.id)
      end

      @doc """
      Complete a workitem
      """
      @spec complete_workitem(
              application :: WorkflowMetal.Application.t(),
              workitem ::
                WorkflowMetal.Workitem.Workitem.t() | WorkflowMetal.Workitem.Workitem.id(),
              output :: WorkflowMetal.Workitem.Workitem.output()
            ) ::
              WorkflowMetal.Workitem.Workitem.on_complete()
      def complete_workitem(application \\ @application, workitem, output) do
        application.complete_workitem(workitem.id, output)
      end

      @doc """
      Abandon a workitem
      """
      @spec abandon_workitem(
              application :: WorkflowMetal.Application.t(),
              workitem ::
                WorkflowMetal.Workitem.Workitem.t() | WorkflowMetal.Workitem.Workitem.id()
            ) ::
              WorkflowMetal.Workitem.Workitem.on_abandon()
      def abandon_workitem(application \\ @application, workitem) do
        application.abandon_workitem(workitem.id)
      end
    end
  end
end
