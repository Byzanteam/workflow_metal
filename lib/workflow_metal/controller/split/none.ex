defmodule WorkflowMetal.Controller.Split.None do
  @moduledoc false

  @behaviour WorkflowMetal.Controller.Split

  @default_pass_weight 1

  @impl true
  def call(_application, [arc], _token) do
    %{
      arc.id => @default_pass_weight
    }
  end
end
