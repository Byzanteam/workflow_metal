defmodule WorkflowMetal.Case.SupervisorTest do
  use ExUnit.Case, async: true

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  alias WorkflowMetal.Application.WorkflowsSupervisor
  alias WorkflowMetal.Case.Supervisor, as: CaseSupervisor
  alias WorkflowMetal.Storage.Schema

  setup_all do
    start_supervised!(DummyApplication)

    [application: DummyApplication]
  end

  describe ".open_case/2" do
    test "failed to open a non-existing workflow" do
      assert {:error, :case_not_found} = CaseSupervisor.open_case(DummyApplication, 123)
    end

    test "failed to open a non-existing case" do
      {:ok, _workflow_schema} =
        WorkflowMetal.Support.Workflows.SequentialRouting.create(DummyApplication)

      assert {:error, :case_not_found} = CaseSupervisor.open_case(DummyApplication, 123)
    end

    test "open a case successfully" do
      {:ok, workflow_schema} =
        WorkflowMetal.Support.Workflows.SequentialRouting.create(DummyApplication)

      {:ok, case_schema} =
        WorkflowMetal.Storage.create_case(
          DummyApplication,
          %Schema.Case.Params{
            workflow_id: workflow_schema.id
          }
        )

      assert {:ok, pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      assert is_pid(pid)
    end
  end
end
