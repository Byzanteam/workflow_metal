defmodule WorkflowMetal.Support.InMemoryStorageCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias WorkflowMetal.Storage.Schema

  using do
    quote do
      alias WorkflowMetal.Storage.Schema

      defmodule DummyApplication do
        @moduledoc false

        use WorkflowMetal.Application,
          storage: WorkflowMetal.Storage.Adapters.InMemory
      end

      import unquote(__MODULE__)

      setup_all do
        start_supervised!(DummyApplication)

        [application: DummyApplication]
      end
    end
  end

  def generate_genesis_token(application, workflow_schema, case_schema) do
    {:ok, {start_place, _end_place}} =
      WorkflowMetal.Storage.fetch_edge_places(application, workflow_schema.id)

    params = %{
      workflow_id: workflow_schema.id,
      place_id: start_place.id,
      case_id: case_schema.id,
      produced_by_task_id: :genesis
    }

    token_id = WorkflowMetal.Storage.generate_id(application, :token, params)

    genesis_token_schema =
      struct(
        Schema.Token,
        Map.merge(params, %{id: token_id, payload: nil})
      )

    WorkflowMetal.Storage.issue_token(application, genesis_token_schema)
  end

  def insert_case(application, %Schema.Workflow{} = workflow_schema) do
    case_id = :erlang.unique_integer([:positive, :monotonic])

    WorkflowMetal.Storage.insert_case(
      application,
      %Schema.Case{
        id: case_id,
        state: :created,
        workflow_id: workflow_schema.id
      }
    )
  end
end
