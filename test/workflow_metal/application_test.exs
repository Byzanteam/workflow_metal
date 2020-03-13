defmodule WorkflowMetal.ApplicationTest do
  use ExUnit.Case

  defmodule Application do
    use WorkflowMetal.Application, name: __MODULE__.TestApplication
  end

  test "build an application" do
    assert {:ok, _pid} = Application.start_link()
    assert Application.supervisor_name() === __MODULE__.Application.TestApplication
  end
end
