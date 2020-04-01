alias WorkflowMetal.Storage.Schema

defmodule Airbase.ProjectWorkflow do
  use WorkflowMetal.Application,
    registry: WorkflowMetal.Registration.LocalRegistry,
    storage: WorkflowMetal.Storage.Adapters.InMemory
end

Airbase.ProjectWorkflow.start_link()
{adapter, storage} = WorkflowMetal.Application.storage_adapter(Airbase.ProjectWorkflow)

# (1) -> [1] -> (2) -> [2] -> (3)
{:ok, workflow_schema} =
  WorkflowMetal.Storage.Adapters.InMemory.create_workflow(
    storage,
    %Schema.Workflow.Params{
      state: :drafted,
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
