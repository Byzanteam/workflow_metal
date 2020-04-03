defmodule WorkflowMetal.Support.Workflows.SequentialRouting do
  @moduledoc false

  alias WorkflowMetal.Storage.Schema

  defmodule SimpleTransition do
    @moduledoc false

    @behaviour WorkflowMetal.Executor

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{}, _tokens, _options) do
      {:completed, %{}}
    end
  end

  defmodule EchoTransition do
    @moduledoc false

    @behaviour WorkflowMetal.Executor

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{}, _tokens, options) do
      executer_params = Keyword.fetch!(options, :executer_params)
      request = Keyword.fetch!(executer_params, :request)
      reply = Keyword.fetch!(executer_params, :reply)

      send(request, reply)

      {:completed, %{}}
    end
  end

  def create(application, executers \\ []) do
    a_transition = Keyword.get_lazy(executers, :a, fn -> build_simple_transition(1) end)
    b_transition = Keyword.get_lazy(executers, :b, fn -> build_simple_transition(2) end)

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

  def build_simple_transition(rid) do
    %Schema.Transition.Params{
      rid: rid,
      executer: SimpleTransition
    }
  end

  def build_echo_transition(rid, params \\ []) do
    %Schema.Transition.Params{
      rid: rid,
      executer: EchoTransition,
      executer_params: Keyword.put_new(params, :request, self())
    }
  end
end
