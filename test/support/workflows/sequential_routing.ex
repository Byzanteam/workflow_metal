defmodule WorkflowMetal.Support.Workflows.SequentialRouting do
  @moduledoc false

  alias WorkflowMetal.Storage.Schema

  defmodule SimpleTransition do
    @moduledoc false

    use WorkflowMetal.Executor

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      {:ok, _tokens} = lock_tokens(options[:application], workitem)

      {:completed, :ok}
    end
  end

  defmodule EchoTransition do
    @moduledoc false

    use WorkflowMetal.Executor

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      {:ok, _tokens} = lock_tokens(options[:application], workitem)

      executor_params = Keyword.fetch!(options, :executor_params)

      request = Keyword.fetch!(executor_params, :request)
      reply = Keyword.fetch!(executor_params, :reply)

      send(request, reply)

      {:completed, %{reply: reply}}
    end
  end

  defmodule AsynchronousTransition do
    @moduledoc false

    use WorkflowMetal.Executor

    @impl true
    def execute(_workitem, options) do
      executor_params = Keyword.fetch!(options, :executor_params)

      request = Keyword.fetch!(executor_params, :request)
      reply = Keyword.fetch!(executor_params, :reply)

      send(request, reply)

      :started
    end
  end

  @doc false
  def create(application, executors \\ []) do
    a_transition = Keyword.get_lazy(executors, :a, fn -> build_simple_transition(1) end)
    b_transition = Keyword.get_lazy(executors, :b, fn -> build_simple_transition(2) end)

    WorkflowMetal.Storage.create_workflow(
      application,
      %Schema.Workflow.Params{
        places: [
          %Schema.Place.Params{rid: 1, type: :start},
          %Schema.Place.Params{rid: 2, type: :normal},
          %Schema.Place.Params{rid: 3, type: :end}
        ],
        transitions: [
          a_transition,
          b_transition
        ],
        arcs: [
          %Schema.Arc.Params{place_rid: 1, transition_rid: 1, direction: :out},
          %Schema.Arc.Params{place_rid: 2, transition_rid: 1, direction: :in},
          %Schema.Arc.Params{place_rid: 2, transition_rid: 2, direction: :out},
          %Schema.Arc.Params{place_rid: 3, transition_rid: 2, direction: :in}
        ]
      }
    )
  end

  @doc false
  def build_simple_transition(rid) do
    %Schema.Transition.Params{
      rid: rid,
      executor: SimpleTransition
    }
  end

  @doc false
  def build_echo_transition(rid, params \\ []) do
    %Schema.Transition.Params{
      rid: rid,
      executor: EchoTransition,
      executor_params: Keyword.put_new(params, :request, self())
    }
  end

  @doc false
  def build_asynchronous_transition(rid, params \\ []) do
    %Schema.Transition.Params{
      rid: rid,
      executor: AsynchronousTransition,
      executor_params: Keyword.put_new(params, :request, self())
    }
  end

  @doc false
  def build_transition(rid, executor, executor_params) do
    %Schema.Transition.Params{
      rid: rid,
      executor: executor,
      executor_params: executor_params
    }
  end
end
