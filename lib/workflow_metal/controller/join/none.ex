defmodule WorkflowMetal.Controller.Join.None do
  @moduledoc """
  The default join controller.

  There is only one branch of the transition.
  """

  @behaviour WorkflowMetal.Controller.Join

  alias WorkflowMetal.Storage.Schema

  @impl WorkflowMetal.Controller.Join
  def task_enablement(task_data) do
    case get_token(task_data) do
      {:error, _reason} = error -> error
      {:ok, _token_ids} -> :ok
    end
  end

  @impl WorkflowMetal.Controller.Join
  def preexecute(task_data) do
    get_token(task_data)
  end

  defp get_token(task_data) do
    %{
      application: application,
      transition_schema: transition_schema,
      token_table: token_table
    } = task_data

    {:ok, [%Schema.Place{id: place_id}]} = WorkflowMetal.Storage.fetch_places(application, transition_schema.id, :in)

    match_spec = [
      {
        {:"$1", %{place_id: place_id}, :_},
        [],
        [:"$1"]
      }
    ]

    case :ets.select(token_table, match_spec) do
      [token_id | _rest] ->
        {:ok, [token_id]}

      _other ->
        {:error, :task_not_enabled}
    end
  end
end
