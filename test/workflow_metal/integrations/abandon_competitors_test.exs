defmodule WorkflowMetal.Integrations.AbandonCompetitorsTest do
  use ExUnit.Case, async: true
  use WorkflowMetal.Support.InMemoryStorageCase

  import WorkflowMetal.Helpers.Wait

  alias WorkflowMetal.Case.Supervisor, as: CaseSupervisor

  alias WorkflowMetal.Support.Workflows.DeferredChoiceRouting.{
    ManualTransition,
    SimpleTransition
  }

  alias WorkflowMetal.Storage.Adapters.InMemory, as: InMemoryStorage

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      storage: InMemoryStorage
  end

  test "abandon competitors between b and c transitions", %{workflow_schema: workflow_schema} do
    {:ok, case_schema} =
      WorkflowMetal.Storage.create_case(
        DummyApplication,
        %Schema.Case.Params{
          workflow_id: workflow_schema.id
        }
      )

    assert {:ok, pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

    assert_receive {2, b_callback}
    assert_receive {3, _c_callback}

    b_callback.()

    until(fn ->
      assert_receive {3, :abandoned}
    end)
  end

  setup_all do
    start_supervised!(DummyApplication)

    [application: DummyApplication]
  end

  setup do
    a_transition = build_simple_transition(1)
    b_transition = build_manul_transition(2)
    c_transition = build_manul_transition(3)
    d_transition = build_manul_transition(4)
    e_transition = build_manul_transition(5)
    f_transition = build_simple_transition(6)

    {:ok, workflow_schema} =
      WorkflowMetal.Storage.create_workflow(
        DummyApplication,
        %Schema.Workflow.Params{
          places: build_places(1..7),
          transitions: [
            a_transition,
            b_transition,
            c_transition,
            d_transition,
            e_transition,
            f_transition
          ],
          arcs:
            build_arcs([
              {1, 1, :out},
              {2, 1, :in},
              {2, 2, :out},
              {2, 3, :out},
              {3, 2, :in},
              {4, 3, :in},
              {3, 4, :out},
              {4, 5, :out},
              {5, 4, :in},
              {6, 5, :in},
              {5, 6, :out},
              {6, 6, :out},
              {7, 6, :in}
            ])
        }
      )

    [workflow_schema: workflow_schema]
  end

  defp build_places(range) do
    first..last = range

    for id <- range do
      case id do
        ^first ->
          %Schema.Place.Params{id: id, type: :start}

        ^last ->
          %Schema.Place.Params{id: id, type: :end}

        _ ->
          %Schema.Place.Params{id: id, type: :normal}
      end
    end
  end

  defp build_arcs(pairs) do
    Enum.map(pairs, fn {place_id, transition_id, direction} ->
      %Schema.Arc.Params{place_id: place_id, transition_id: transition_id, direction: direction}
    end)
  end

  defp build_simple_transition(id) do
    %Schema.Transition.Params{
      id: id,
      executor: SimpleTransition
    }
  end

  defp build_manul_transition(id) do
    %Schema.Transition.Params{
      id: id,
      executor: ManualTransition,
      executor_params: [request: self(), id: id]
    }
  end
end
