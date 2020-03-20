defmodule WorkflowMetal.ApplicationTest do
  use ExUnit.Case

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      name: __MODULE__.TestApplication,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  alias DummyApplication.TestApplication
  alias WorkflowMetal.Application.Config

  test "build an application" do
    start_supervised(DummyApplication)

    assert Config.get(TestApplication, :registry)
  end

  test "create workflow" do
    start_supervised(DummyApplication)

    assert {:ok, _pid} =
             DummyApplication.create_workflow(TestApplication,
               workflow_id: 123,
               workflow_version: "1"
             )
  end
end
