alias WorkflowMetal.Storage.Schema

defmodule Airbase.ProjectWorkflow do
  use WorkflowMetal.Application,
    registry: WorkflowMetal.Registration.LocalRegistry,
    storage: WorkflowMetal.Storage.Adapters.InMemory
end

Airbase.ProjectWorkflow.start_link()

# (1) -> [1] -> (2) -> [2] -> (3)
{:ok, workflow_schema} =
  WorkflowMetal.Storage.insert_workflow(
    Airbase.ProjectWorkflow,
    %Schema.Workflow.Params{
      places: [
        %Schema.Place.Params{id: 1, type: :start},
        %Schema.Place.Params{id: 2, type: :normal},
        %Schema.Place.Params{id: 3, type: :end}
      ],
      transitions: [
        %Schema.Transition.Params{id: 1, executor: A},
        %Schema.Transition.Params{id: 2, executor: B}
      ],
      arcs: [
        %Schema.Arc.Params{place_id: 1, transition_id: 1, direction: :out},
        %Schema.Arc.Params{place_id: 2, transition_id: 1, direction: :in},
        %Schema.Arc.Params{place_id: 2, transition_id: 2, direction: :out},
        %Schema.Arc.Params{place_id: 3, transition_id: 2, direction: :in}
      ]
    }
  )
