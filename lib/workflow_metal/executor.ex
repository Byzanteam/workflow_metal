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
          {:ok, _tokens} = lock_tokens(workitem, options)

          {:completed, {:output, :ok}}
        end
      end

      defmodule AsyncExampleExecutor do
        use WorkflowMetal.Executor

        alias WorkflowMetal.Storage.Schema

        @impl WorkflowMetal.Executor
        def execute(%Schema.Workitem{} = workitem, options) do
          {:ok, tokens} = lock_tokens(workitem, options)

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
  defmacro __using__(_opts) do
    quote do
      @behaviour WorkflowMetal.Executor

      @impl WorkflowMetal.Executor
      def build_token_payload(workitems, _options) do
        {:ok, Enum.map(workitems, & &1.output)}
      end

      defoverridable WorkflowMetal.Executor

      defp lock_tokens(workitem, options) do
        application = Keyword.fetch!(options, :application)
        application.lock_tokens(workitem.task_id)
      end
    end
  end
end
