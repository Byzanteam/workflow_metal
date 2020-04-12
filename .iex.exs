alias WorkflowMetal.Storage.Schema

defmodule Airbase.ProjectWorkflow do
  use WorkflowMetal.Application,
    registry: WorkflowMetal.Registration.LocalRegistry,
    storage: WorkflowMetal.Storage.Adapters.InMemory
end

Airbase.ProjectWorkflow.start_link()

# (1) -> [1] -> (2) -> [2] -> (3)
{:ok, workflow_schema} =
  WorkflowMetal.Storage.create_workflow(
    Airbase.ProjectWorkflow,
    %Schema.Workflow.Params{
      places: [
        %Schema.Place.Params{rid: 1, type: :start},
        %Schema.Place.Params{rid: 2, type: :normal},
        %Schema.Place.Params{rid: 3, type: :end}
      ],
      transitions: [
        %Schema.Transition.Params{rid: 1, executor: A},
        %Schema.Transition.Params{rid: 2, executor: B}
      ],
      arcs: [
        %Schema.Arc.Params{place_rid: 1, transition_rid: 1, direction: :out},
        %Schema.Arc.Params{place_rid: 2, transition_rid: 1, direction: :in},
        %Schema.Arc.Params{place_rid: 2, transition_rid: 2, direction: :out},
        %Schema.Arc.Params{place_rid: 3, transition_rid: 2, direction: :in}
      ]
    }
  )
