defmodule WorkflowMetal.Integrations.AbandonCompetitorsTest do
  use ExUnit.Case, async: true
  use WorkflowMetal.Support.InMemoryStorageCase

  import WorkflowMetal.Helpers.Wait

  alias WorkflowMetal.Case.Supervisor, as: CaseSupervisor

  alias WorkflowMetal.Support.Workflows.DeferredChoiceRouting.{
    ManualTransition,
    SimpleTransition
  }

  setup do
    params = %{workflow_id: 1}

    a_transition = build_simple_transition(1, params)
    b_transition = build_manul_transition(2, params)
    c_transition = build_manul_transition(3, params)
    d_transition = build_manul_transition(4, params)
    e_transition = build_manul_transition(5, params)
    f_transition = build_simple_transition(6, params)

    {:ok, workflow_schema} =
      WorkflowMetal.Storage.insert_workflow(
        DummyApplication,
        %Schema.Workflow{
          id: 1,
          state: :active
        },
        %{
          places: build_places(1..7, params),
          transitions: [
            a_transition,
            b_transition,
            c_transition,
            d_transition,
            e_transition,
            f_transition
          ],
          arcs:
            build_arcs(
              [
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
              ],
              params
            )
        }
      )

    [workflow_schema: workflow_schema]
  end

  test "abandon competitors between b and c transitions", %{workflow_schema: workflow_schema} do
    {:ok, case_schema} = insert_case(DummyApplication, workflow_schema)

    assert {:ok, _pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

    assert_receive {2, b_callback}
    assert_receive {3, _c_callback}

    b_callback.()

    until(fn ->
      assert_receive {3, :abandoned}
    end)
  end

  defp build_places(range, params) do
    first..last = range

    for id <- range do
      place_type =
        case id do
          ^first ->
            :start

          ^last ->
            :end

          _ ->
            :normal
        end

      struct(
        Schema.Place,
        Map.merge(%{id: id, type: place_type}, params)
      )
    end
  end

  defp build_arcs(pairs, params) do
    pairs
    |> Enum.with_index()
    |> Enum.map(fn {{place_id, transition_id, direction}, index} ->
      struct(
        Schema.Arc,
        Map.merge(
          %{
            id: index,
            place_id: place_id,
            transition_id: transition_id,
            direction: direction
          },
          params
        )
      )
    end)
  end

  defp build_simple_transition(id, params) do
    struct(
      Schema.Transition,
      Map.merge(
        %{
          join_type: :none,
          split_type: :none,
          id: id,
          executor: SimpleTransition
        },
        params
      )
    )
  end

  defp build_manul_transition(id, params) do
    struct(
      Schema.Transition,
      Map.merge(
        %{
          id: id,
          join_type: :none,
          split_type: :none,
          executor: ManualTransition,
          executor_params: [request: self(), id: id]
        },
        params
      )
    )
  end
end
