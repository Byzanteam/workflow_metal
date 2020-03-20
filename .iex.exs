defmodule Airbase.ProjectWorkflow do
  use WorkflowMetal.Application,
    registry: WorkflowMetal.Registration.LocalRegistry,
    storage: WorkflowMetal.Storage.Adapters.InMemory
end
