defmodule WorkflowMetal.ApplicationTest do
  use ExUnit.Case

  defmodule DummyApplication do
    use WorkflowMetal.Application, name: __MODULE__.TestApplication
  end

  test "build an application" do
    start_supervised(DummyApplication)

    assert WorkflowMetal.Application.Config.get(__MODULE__.DummyApplication.TestApplication, :registry)
  end

  test "create workflow" do
    start_supervised(DummyApplication)
    assert {:ok, _pid} = DummyApplication.create_workflow(DummyApplication.TestApplication, [workflow_id: 123])
  end
end
