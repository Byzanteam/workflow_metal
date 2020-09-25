defmodule WorkflowMetal.Controller.Split.And do
  @moduledoc false

  alias WorkflowMetal.Storage.Schema

  @behaviour WorkflowMetal.Controller.Split

  @impl true
  def issue_tokens(task_data, token_payload) do
    %{
      application: application,
      task_schema: %Schema.Task{
        id: task_id,
        workflow_id: workflow_id,
        transition_id: transition_id,
        case_id: case_id
      }
    } = task_data

    {:ok, arcs} =
      WorkflowMetal.Storage.fetch_arcs(
        application,
        {:transition, transition_id},
        :out
      )

    {
      :ok,
      Enum.map(arcs, fn arc ->
        params = %{
          workflow_id: workflow_id,
          place_id: arc.place_id,
          case_id: case_id,
          produced_by_task_id: task_id
        }

        token_id = WorkflowMetal.Storage.generate_id(application, :token, params)

        struct(
          Schema.Token,
          Map.merge(params, %{id: token_id, payload: token_payload, state: :free})
        )
      end)
    }
  end
end
