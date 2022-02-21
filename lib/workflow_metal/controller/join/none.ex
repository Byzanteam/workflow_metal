defmodule WorkflowMetal.Controller.Join.None do
  @moduledoc """
  The default join controller.

  There is only one branch of the transition.
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

    {:ok, [%Schema.Place{id: place_id}]} =
      WorkflowMetal.Storage.fetch_places(application, transition_schema.id, :in)

    match_spec = [
      {
        {:"$1", %{place_id: place_id}, :_},
        [],
        [:"$1"]
      }
    ]

    case :ets.select(token_table, match_spec) do
      [_token_id | _rest] ->
        :ok

      _ ->
        {:error, :task_not_enabled}
    end
  end
end
