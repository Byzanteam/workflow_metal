defmodule WorkflowMetal.ApplicationTest do
  use ExUnit.Case, async: true

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      name: __MODULE__.TestApplication,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  alias WorkflowMetal.Application.Config

  alias DummyApplication.TestApplication

  test "build an application" do
    start_supervised(DummyApplication)

    assert Config.get(TestApplication, :registry)
  end
end
