defmodule WorkflowMetal.ApplicationTest do
  use ExUnit.Case, async: true

  alias WorkflowMetal.Application.Config

  defmodule DummyApplication do
    @moduledoc false
    use WorkflowMetal.Application,
      name: __MODULE__.TestApplication,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  test "build an application" do
    start_supervised!(DummyApplication)

    assert Config.get(DummyApplication.TestApplication, :registry)
  end
end
