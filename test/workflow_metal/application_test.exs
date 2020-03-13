defmodule WorkflowMetal.ApplicationTest do
  use ExUnit.Case

  defmodule Application do
    use WorkflowMetal.Application, name: __MODULE__.TestApplication
  end

  test "build an application" do
    assert {:ok, _pid} = Application.start()
  end
end
