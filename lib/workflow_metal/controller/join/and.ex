defmodule WorkflowMetal.Controller.Join.And do
  @moduledoc """
  All incoming branch are active.
  """

  @behaviour WorkflowMetal.Controller.Join

  alias WorkflowMetal.Storage.Schema

  @impl WorkflowMetal.Controller.Join
  def task_enablement(task_data) do
    case get_tokens(task_data) do
      {:error, _reason} = error -> error
      {:ok, _token_ids} -> :ok
    end
  end

  @impl WorkflowMetal.Controller.Join
  def preexecute(task_data) do
    get_tokens(task_data)
  end

  defp get_tokens(task_data) do
    %{
      application: application,
      transition_schema: transition_schema,
      token_table: token_table
    } = task_data

    {:ok, places} = WorkflowMetal.Storage.fetch_places(application, transition_schema.id, :in)

    places
    |> Enum.reduce_while([], fn %Schema.Place{} = place, token_ids ->
      match_spec = [
        {
          {:"$1", %{place_id: place.id}, :_},
          [],
          [:"$1"]
        }
      ]

      case :ets.select(token_table, match_spec) do
        [token_id | _rest] ->
          {:cont, [token_id | token_ids]}

        _ ->
          {:halt, {:error, :task_not_enabled}}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      [] -> {:error, :tokens_not_available}
      [_ | _] = token_ids -> {:ok, token_ids}
    end
  end
end
