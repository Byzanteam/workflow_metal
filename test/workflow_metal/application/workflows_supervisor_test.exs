defmodule WorkflowMetal.Application.WorkflowsSupervisorTest do
  use ExUnit.Case, async: true

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  alias WorkflowMetal.Application.WorkflowsSupervisor
  alias WorkflowMetal.Support.Workflows.SequentialRouting

  setup_all do
    start_supervised!(DummyApplication)

    [application: DummyApplication]
  end

  describe ".open_workflow/2" do
    test "failed to open a non-existing workflow" do
      assert {:error, :workflow_not_found} =
               WorkflowsSupervisor.open_workflow(DummyApplication, 123)
    end

    test "open a sequential_routing workflow successfully" do
      {:ok, workflow_schema} = SequentialRouting.create(DummyApplication)

      assert {:ok, pid} = WorkflowsSupervisor.open_workflow(DummyApplication, workflow_schema.id)
      assert is_pid(pid)
    end
  end
end
