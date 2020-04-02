defmodule WorkflowMetal.Support.Workflows.SequentialRouting do
  alias WorkflowMetal.Storage.Schema

  def create(application) do
    WorkflowMetal.Storage.create_workflow(
      application,
      %Schema.Workflow.Params{
        places: [
          %Schema.Place.Params{rid: 1, type: :start},
          %Schema.Place.Params{rid: 2, type: :normal},
          %Schema.Place.Params{rid: 3, type: :end}
        ],
        transitions: [
          %Schema.Transition.Params{rid: 1, executer: A},
          %Schema.Transition.Params{rid: 2, executer: B}
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
end
