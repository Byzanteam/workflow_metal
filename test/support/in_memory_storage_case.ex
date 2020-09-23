defmodule WorkflowMetal.Support.InMemoryStorageCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      alias WorkflowMetal.Storage.Schema

      def generate_genesis_token(application, workflow_schema, case_schema) do
        {:ok, {start_place, _end_place}} =
          WorkflowMetal.Storage.fetch_edge_places(application, workflow_schema.id)

        genesis_token_params = %Schema.Token.Params{
          workflow_id: workflow_schema.id,
          place_id: start_place.id,
          case_id: case_schema.id,
          produced_by_task_id: :genesis,
          payload: nil
        }

        WorkflowMetal.Storage.issue_token(application, genesis_token_params)
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
  end
end
