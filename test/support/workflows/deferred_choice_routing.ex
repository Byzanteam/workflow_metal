defmodule WorkflowMetal.Support.Workflows.DeferredChoiceRouting do
  @moduledoc false

  alias WorkflowMetal.Storage.Schema

  defmodule SimpleTransition do
    @moduledoc false

    use WorkflowMetal.Executor

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      {:ok, _tokens} = preexecute(options[:application], workitem)

      {:completed, :ok}
    end
  end

  defmodule ManualTransition do
    @moduledoc false

    use WorkflowMetal.Executor

    @impl true
    def execute(workitem, options) do
      executor_params = Keyword.fetch!(options, :executor_params)
      request = Keyword.fetch!(executor_params, :request)
      id = Keyword.fetch!(executor_params, :id)

      callback = fn ->
        with({:ok, _tokens} <- preexecute(options[:application], workitem)) do
          complete_workitem(options[:application], workitem, %{})
        end
      end

      send(request, {id, callback})

      :started
    end

    @impl true
    def abandon(_workitem, options) do
      executor_params = Keyword.fetch!(options, :executor_params)
      request = Keyword.fetch!(executor_params, :request)
      id = Keyword.fetch!(executor_params, :id)

      send(request, {id, :abandoned})

      :ok
    end
  end
end
