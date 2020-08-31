defmodule WorkflowMetal.Support.Workflows.SequentialRouting do
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

  defmodule EchoTransition do
    @moduledoc false

    use WorkflowMetal.Executor

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      {:ok, _tokens} = preexecute(options[:application], workitem)

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

    @impl WorkflowMetal.Executor
    def abandon(%Schema.Workitem{}, options) do
      executor_params = Keyword.fetch!(options, :executor_params)

      request = Keyword.fetch!(executor_params, :request)
      reply = Keyword.fetch!(executor_params, :abandon_reply)

      send(request, reply)

      :ok
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
          %Schema.Place.Params{id: 1, type: :start},
          %Schema.Place.Params{id: 2, type: :normal},
          %Schema.Place.Params{id: 3, type: :end}
        ],
        transitions: [
          a_transition,
          b_transition
        ],
        arcs: [
          %Schema.Arc.Params{place_id: 1, transition_id: 1, direction: :out},
          %Schema.Arc.Params{place_id: 2, transition_id: 1, direction: :in},
          %Schema.Arc.Params{place_id: 2, transition_id: 2, direction: :out},
          %Schema.Arc.Params{place_id: 3, transition_id: 2, direction: :in}
        ]
      }
    )
  end

  @doc false
  def build_simple_transition(id) do
    %Schema.Transition.Params{
      id: id,
      executor: SimpleTransition
    }
  end

  @doc false
  def build_echo_transition(id, params \\ []) do
    %Schema.Transition.Params{
      id: id,
      executor: EchoTransition,
      executor_params: Keyword.put_new(params, :request, self())
    }
  end

  @doc false
  def build_asynchronous_transition(id, params \\ []) do
    %Schema.Transition.Params{
      id: id,
      executor: AsynchronousTransition,
      executor_params: Keyword.put_new(params, :request, self())
    }
  end

  @doc false
  def build_transition(id, executor, executor_params) do
    %Schema.Transition.Params{
      id: id,
      executor: executor,
      executor_params: executor_params
    }
  end
end
