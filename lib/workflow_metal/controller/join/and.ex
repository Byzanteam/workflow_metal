defmodule WorkflowMetal.Controller.Join.And do
  @moduledoc """
  All incoming branch are active.
  """

  alias WorkflowMetal.Storage.Schema

  @behaviour WorkflowMetal.Controller.Join

  @impl WorkflowMetal.Controller.Join
  def task_enablement(task_data) do
    %{
      application: application,
      transition_schema: transition_schema,
      token_table: token_table
    } = task_data

    {:ok, places} = WorkflowMetal.Storage.fetch_places(application, transition_schema.id, :in)

    Enum.reduce_while(places, {:ok, []}, fn %Schema.Place{} = place, {:ok, token_ids} ->
      match_spec = [
        {
          {:"$1", %{place_id: :"$2"}, :_},
          [{:"=:=", {:const, place.id}, :"$2"}],
          [:"$1"]
        }
      ]

      case :ets.select(token_table, match_spec) do
        [token_id | _rest] ->
          {:cont, {:ok, [token_id | token_ids]}}

        _ ->
          {:halt, {:error, :task_not_enabled}}
      end
    end)
  end
end
