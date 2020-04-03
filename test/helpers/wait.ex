defmodule WorkflowMetal.Helpers.Wait do
  @moduledoc false

  def until(fun), do: until(500, fun)

  def until(0, fun), do: fun.()

  def until(timeout, fun) do
    fun.()
  rescue
    ExUnit.AssertionError ->
      :timer.sleep(10)
      until(max(0, timeout - 10), fun)
  end
end
