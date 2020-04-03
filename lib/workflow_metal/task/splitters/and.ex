defmodule WorkflowMetal.Task.Splitters.And do
  @moduledoc false

  @behaviour WorkflowMetal.Task.Splitter.ConcreteSplitter

  @default_pass_weight 1

  @doc false
  @impl true
  def call(_application, arcs, _token) do
    Enum.into(arcs, %{}, fn arc ->
      {arc.id, @default_pass_weight}
    end)
  end
end
