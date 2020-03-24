defmodule WorkflowMetal.Application.WorkflowsSupervisorTest do
  use ExUnit.Case

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  alias WorkflowMetal.Application.WorkflowsSupervisor

  describe ".open_workflow/2" do
    test "failed to open a non-existing workflow" do
      start_supervised(DummyApplication)

      assert {:error, :workflow_not_found} =
               WorkflowsSupervisor.open_workflow(DummyApplication, 123)
    end

    test "open a workflow successfully" do
      start_supervised(DummyApplication)

      assert {:ok, :created} = WorkflowsSupervisor.create_workflow(DummyApplication, 123, [])
      assert {:ok, pid} = WorkflowsSupervisor.open_workflow(DummyApplication, 123)
      assert is_pid(pid)
    end
  end
end
