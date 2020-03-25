defmodule WorkflowMetal.ApplicationTest do
  use ExUnit.Case

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      name: __MODULE__.TestApplication,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  alias WorkflowMetal.Application.Config
  alias WorkflowMetal.Storage.Schema

  alias DummyApplication.TestApplication

  test "build an application" do
    start_supervised(DummyApplication)

    assert Config.get(TestApplication, :registry)
  end

  test "create workflow" do
    start_supervised(DummyApplication)

    workflow_schema = %Schema.Workflow{id: 123}
    assert :ok = DummyApplication.create_workflow(workflow_schema)
  end
end
