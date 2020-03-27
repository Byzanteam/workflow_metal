defmodule WorkflowMetal.Workflow.WorkflowTest do
  use ExUnit.Case

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  alias WorkflowMetal.Application.WorkflowsSupervisor
  alias WorkflowMetal.Storage.Schema
  alias WorkflowMetal.Workflow.Workflow

  describe ".fetch_transitions/3 and .fetch_places/3" do
    test "fetch successfully" do
      start_supervised(DummyApplication)

      # [Start(place)] -arc-1-> [A(transition)] -arc-2-> [B(place)]
      # -arc-3-> [C(transition)] -arc-4-> [D(place)] -arc-5-> [E(transition)]
      # -arc-6-> [End(place)]

      workflow_id = 1

      start_place = %Schema.Place{
        id: "Start",
        workflow_id: workflow_id,
        type: :start
      }

      b_place = %Schema.Place{
        id: "B",
        workflow_id: workflow_id,
        type: :normal
      }

      d_place = %Schema.Place{
        id: "D",
        workflow_id: workflow_id,
        type: :normal
      }

      end_place = %Schema.Place{
        id: "End",
        workflow_id: workflow_id,
        type: :end
      }

      places = [start_place, b_place, d_place, end_place]

      a_transition = %Schema.Transition{
        id: "A",
        workflow_id: workflow_id
      }

      c_transition = %Schema.Transition{
        id: "C",
        workflow_id: workflow_id
      }

      e_transition = %Schema.Transition{
        id: "E",
        workflow_id: workflow_id
      }

      transitions = [a_transition, c_transition, e_transition]

      arcs = [
        %Schema.Arc{
          id: "1",
          workflow_id: workflow_id,
          place_id: "Start",
          transition_id: "A",
          direction: :out
        },
        %Schema.Arc{
          id: "2",
          workflow_id: workflow_id,
          place_id: "B",
          transition_id: "A",
          direction: :in
        },
        %Schema.Arc{
          id: "1",
          workflow_id: workflow_id,
          place_id: "B",
          transition_id: "C",
          direction: :out
        },
        %Schema.Arc{
          id: "1",
          workflow_id: workflow_id,
          place_id: "D",
          transition_id: "C",
          direction: :in
        },
        %Schema.Arc{
          id: "1",
          workflow_id: workflow_id,
          place_id: "D",
          transition_id: "E",
          direction: :out
        },
        %Schema.Arc{
          id: "1",
          workflow_id: workflow_id,
          place_id: "End",
          transition_id: "E",
          direction: :in
        }
      ]

      workflow_schema = %Schema.Workflow{
        id: workflow_id,
        places: places,
        transitions: transitions,
        arcs: arcs
      }

      assert :ok = WorkflowsSupervisor.create_workflow(DummyApplication, workflow_schema)
      assert {:ok, _pid} = WorkflowsSupervisor.open_workflow(DummyApplication, workflow_schema.id)

      workflow_server = Workflow.via_name(DummyApplication, workflow_id)

      # fetch_transitions
      assert Workflow.fetch_transitions(workflow_server, start_place.id, :in) === []
      assert Workflow.fetch_transitions(workflow_server, start_place.id, :out) === [a_transition]

      assert Workflow.fetch_transitions(workflow_server, b_place.id, :in) === [a_transition]
      assert Workflow.fetch_transitions(workflow_server, b_place.id, :out) === [c_transition]
      assert Workflow.fetch_transitions(workflow_server, end_place.id, :out) === []

      # fetch_places
      assert Workflow.fetch_places(workflow_server, a_transition.id, :in) === [start_place]

      assert Workflow.fetch_places(workflow_server, a_transition.id, :out) === [b_place]
    end
  end
end
