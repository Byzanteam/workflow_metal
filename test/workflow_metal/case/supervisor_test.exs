defmodule WorkflowMetal.Case.SupervisorTest do
  use ExUnit.Case, async: true
  use WorkflowMetal.Support.InMemoryStorageCase

  alias WorkflowMetal.Case.Supervisor, as: CaseSupervisor
  alias WorkflowMetal.Support.Workflows.SequentialRouting

  describe ".open_case/2" do
    test "failed to open a non-existing workflow" do
      assert {:error, :case_not_found} = CaseSupervisor.open_case(DummyApplication, 123)
    end

    test "failed to open a non-existing case" do
      {:ok, _workflow_schema} = SequentialRouting.create(DummyApplication)

      assert {:error, :case_not_found} = CaseSupervisor.open_case(DummyApplication, 123)
    end

    test "open a case successfully" do
      {:ok, workflow_schema} = SequentialRouting.create(DummyApplication)

      {:ok, case_schema} = insert_case(DummyApplication, workflow_schema)

      assert {:ok, pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      assert is_pid(pid)
    end
  end
end
