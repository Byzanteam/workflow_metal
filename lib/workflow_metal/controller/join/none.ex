defmodule WorkflowMetal.Controller.Join.None do
  @moduledoc """
  The default join controller.

  There is only one branch of the transition.
  """

  @behaviour WorkflowMetal.Controller.Join

  @impl WorkflowMetal.Controller.Join
  def task_enablement(task_state) do
    %{
      application: application,
      transition_schema: transition_schema,
      token_table: token_table
    } = task_state

    {:ok, [place]} = WorkflowMetal.Storage.fetch_places(application, transition_schema.id, :in)

    case :ets.select(token_table, [{{:"$1", place.id, :free}, [], [:"$1"]}]) do
      [token_id | _rest] ->
        {:ok, [token_id]}

      _ ->
        {:error, :task_not_enabled}
    end
  end
end
