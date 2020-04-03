defmodule WorkflowMetal.Controller.Splitter do
  @moduledoc false

  @type application :: WorkflowMetal.Application.t()
  @type task_schema :: WorkflowMetal.Storage.Schema.Task.t()
  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()
  @type arc_id :: WorkflowMetal.Storage.Schema.Arc.id()

  @type arc_weight :: integer
  @type result ::
          %{required(arc_id) => integer}
          | {:error, :transition_not_found}

  @doc false
  @spec call(application, task_schema, token_schema) :: result
  def call(application, task, token) do
    with(
      {:ok, transition} <-
        WorkflowMetal.Storage.fetch_transition(application, task.transition_id),
      {:ok, arcs} <- WorkflowMetal.Storage.fetch_arcs(application, transition.id, :out),
      {:ok, concrete_splitter} <- concrete_splitter(transition.split_type)
    ) do
      concrete_splitter.call(application, arcs, token)
    end
  end

  alias WorkflowMetal.Controller.Split

  defp concrete_splitter(:none), do: {:ok, Split.None}
  defp concrete_splitter(:and), do: {:ok, Split.And}
end
