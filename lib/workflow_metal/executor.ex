defmodule WorkflowMetal.Executor do
  @moduledoc """
  Defines an executor module.

  The `WorkflowMetal.Executor` behaviour is used to execute the executor.

  ## Supported return values

    - `:started` - the executor is started, and report its state latter, this is useful for long-running tasks(for example: timer).
    - `{:completed, token_params}` - the executor has been started and comploted already.
    - `{:failed, reason}` - the executor failed to execute.

  ## Example
      defmodule ExampleExecutor do
        @behaviour WorkflowMetal.Executor

        alias WorkflowMetal.Storage.Schema

        @impl WorkflowMetal.Executor
        def execute(%Schema.Workitem{}, _tokens) do
          {:completed, %Schema.Token.Params{}}
        end
      end

      defmodule AsyncExampleExecutor do
        @behaviour WorkflowMetal.Executor

        alias WorkflowMetal.Storage.Schema

        @impl WorkflowMetal.Executor
        def execute(%Schema.Workitem{} = workitem, tokens) do
          Task.async(__MODULE__, :run, [workitem, tokens])
          :started
        end

        def run(%Schema.Workitem{} = workitem, _tokens) do
          WorkflowMetal.WorkitemSupervisor.complete(workitem, %Schema.Token.Params{})
        end
      end
  """

  @type error :: term()
  @type workitem :: WorkflowMetal.Storage.Schema.Workitem.t()
  @type token :: WorkflowMetal.Storage.Schema.Token.t()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()

  @doc """
  Run an executor and return its state to the `workitem` process.
  """
  @callback execute(workitem, nonempty_list(token)) ::
              :started
              | {:completed, token_params}
              | {:failed, error}
end
