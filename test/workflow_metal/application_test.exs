defmodule WorkflowMetal.ApplicationTest do
  use ExUnit.Case

  defmodule DummyApplication do
    use WorkflowMetal.Application, name: __MODULE__.TestApplication
  end

  alias DummyApplication.TestApplication
  alias WorkflowMetal.Application.Config

  test "build an application" do
    start_supervised(DummyApplication)

    assert Config.get(TestApplication, :registry)
  end

  test "create workflow" do
    start_supervised(DummyApplication)

    assert {:ok, _pid} = DummyApplication.create_workflow(TestApplication, id: 123, version: "1")
  end
end
