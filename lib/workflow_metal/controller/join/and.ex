defmodule WorkflowMetal.Controller.Join.And do
  @moduledoc """
  All incoming branch are active.
  """

  @behaviour WorkflowMetal.Controller.Join

  @impl WorkflowMetal.Controller.Join
  def task_enablement(task_data) do
    %{
      application: application,
      transition_schema: transition_schema,
      token_table: token_table
    } = task_data

    {:ok, places} = WorkflowMetal.Storage.fetch_places(application, transition_schema.id, :in)

    Enum.reduce_while(places, {:ok, []}, fn place, {:ok, token_ids} ->
      case :ets.select(token_table, [{{:"$1", place.id, :free}, [], [:"$1"]}]) do
        [token_id | _rest] ->
          {:cont, {:ok, [token_id | token_ids]}}

        _ ->
          {:halt, {:error, :task_not_enabled}}
      end
    end)
  end
end
