defmodule WorkflowMetal.Controller.Split.And do
  @moduledoc false

  @behaviour WorkflowMetal.Controller.Split

  @default_pass_weight 1

  @impl true
  def call(_application, arcs, _token) do
    Enum.into(arcs, %{}, fn arc ->
      {arc.id, @default_pass_weight}
    end)
  end
end
