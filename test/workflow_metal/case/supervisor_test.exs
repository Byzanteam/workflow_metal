defmodule WorkflowMetal.Case.SupervisorTest do
  use ExUnit.Case

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  alias WorkflowMetal.Application.WorkflowsSupervisor
  alias WorkflowMetal.Case.Supervisor, as: CaseSupervisor
  alias WorkflowMetal.Storage.Schema

  describe ".open_case/2" do
    test "failed to open a non-existing workflow" do
      start_supervised(DummyApplication)

      assert {:error, :workflow_not_found} = CaseSupervisor.open_case(DummyApplication, 123, 123)
    end

    test "failed to open a non-existing case" do
      start_supervised(DummyApplication)
      workflow_schema = %Schema.Workflow{id: 123}

      assert :ok = WorkflowsSupervisor.create_workflow(DummyApplication, workflow_schema)
      assert {:error, :case_not_found} = CaseSupervisor.open_case(DummyApplication, 123, 123)
    end

    test "open a case successfully" do
      start_supervised(DummyApplication)

      workflow_schema = %Schema.Workflow{id: 123}
      case_schema = %Schema.Case{id: 123, workflow_id: 123}

      assert :ok = WorkflowsSupervisor.create_workflow(DummyApplication, workflow_schema)
      assert :ok = CaseSupervisor.create_case(DummyApplication, case_schema)

      assert {:ok, pid} =
               CaseSupervisor.open_case(DummyApplication, case_schema.workflow_id, case_schema.id)

      assert is_pid(pid)
    end
  end
end
