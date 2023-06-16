defmodule WorkflowMetal.Controller.Split.None do
  @moduledoc false

  @behaviour WorkflowMetal.Controller.Split

  alias WorkflowMetal.Storage.Schema

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

    {:ok, [arc]} =
      WorkflowMetal.Storage.fetch_arcs(
        application,
        {:transition, transition_id},
        :out
      )

    new_token =
      struct(
        Schema.Token,
        %{
          state: :free,
          payload: token_payload,
          workflow_id: workflow_id,
          place_id: arc.place_id,
          case_id: case_id,
          produced_by_task_id: task_id
        }
      )

    {:ok, [new_token]}
  end
end
