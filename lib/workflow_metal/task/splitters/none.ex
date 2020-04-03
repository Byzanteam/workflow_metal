defmodule WorkflowMetal.Task.Splitters.None do
  @moduledoc false

  @behaviour WorkflowMetal.Task.Splitter.ConcreteSplitter

  @default_pass_weight 1

  @doc false
  @impl true
  def call(_application, [arc], _token) do
    %{
      arc.id => @default_pass_weight
    }
  end
end
