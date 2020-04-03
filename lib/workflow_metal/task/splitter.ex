defmodule WorkflowMetal.Task.Splitter do
  @moduledoc false

  @type application :: WorkflowMetal.Application.t()
  @type task_schema :: WorkflowMetal.Storage.Schema.Task.t()
  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()
  @type arc_id :: WorkflowMetal.Storage.Schema.Arc.id()

  @type arc_weight :: integer
  @type result ::
          %{required(arc_id) => integer}
          | {:error, :invalid_split_type}
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

  alias WorkflowMetal.Task.Splitters

  defp concrete_splitter(:none), do: {:ok, Splitters.None}
  defp concrete_splitter(:and), do: {:ok, Splitters.And}

  alias __MODULE__

  defmodule ConcreteSplitter do
    @moduledoc false

    @type arc_schema :: WorkflowMetal.Storage.Schema.Arc.t()

    @callback call(Splitter.application(), [arc_schema], Splitter.token_schema()) ::
                Splitter.result()
  end
end
