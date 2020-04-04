defmodule WorkflowMetal.Executor do
  @moduledoc """
  Defines an executor module.

  The `WorkflowMetal.Executor` behaviour is used to execute the executor.

  ## Supported return values

    - `:started` - the executor is started, and report its state latter, this is useful for long-running tasks(for example: timer).
    - `{:completed, workitem_output}` - the executor has been started and comploted already.
    - `{:failed, reason}` - the executor failed to execute.

  ## Example
      defmodule ExampleExecutor do
        @behaviour WorkflowMetal.Executor

        alias WorkflowMetal.Storage.Schema

        @impl WorkflowMetal.Executor
        def execute(%Schema.Workitem{}, _tokens, _options) do
          {:completed, {:output, :ok}}
        end
      end

      defmodule AsyncExampleExecutor do
        @behaviour WorkflowMetal.Executor

        alias WorkflowMetal.Storage.Schema

        @impl WorkflowMetal.Executor
        def execute(%Schema.Workitem{} = workitem, tokens, options) do
          Task.async(__MODULE__, :run, [workitem, tokens, options])
          :started
        end

        def run(%Schema.Workitem{} = workitem, _tokens, _options) do
          WorkflowMetal.WorkitemSupervisor.complete(workitem, {:output, :ok})
        end
      end
  """

  @type options :: keyword()
  @type workitem :: WorkflowMetal.Storage.Schema.Workitem.t()
  @type token :: WorkflowMetal.Storage.Schema.Token.t()
  @type token_payload :: WorkflowMetal.Storage.Schema.Token.payload()
  @type workitem_output :: WorkflowMetal.Storage.Schema.Workitem.output()

  @doc """
  Run an executor and return its state to the `workitem` process.
  """
  @callback execute(workitem, nonempty_list(token), options) ::
              :started
              | {:completed, workitem_output}

  @doc """
  Merge outputs of all workitems.
  """
  @callback build_token_payload(nonempty_list(workitem), options) ::
              {:ok, token_payload}
end
