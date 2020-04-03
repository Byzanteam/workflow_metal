defmodule WorkflowMetal.Workitem.WorkitemTest do
  use ExUnit.Case, async: true

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  alias WorkflowMetal.Application.WorkflowsSupervisor
  alias WorkflowMetal.Case.Supervisor, as: CaseSupervisor
  alias WorkflowMetal.Storage.Schema
  alias WorkflowMetal.Support.Workflows.SequentialRouting

  setup_all do
    start_supervised!(DummyApplication)

    [application: DummyApplication]
  end

  describe "activate_case" do
    test "activate a case successfully" do
      {:ok, workflow_schema} =
        SequentialRouting.create(
          DummyApplication,
          a: SequentialRouting.build_echo_transition(1, reply: :a_completed),
          b: SequentialRouting.build_echo_transition(2, reply: :b_completed)
        )

      {:ok, case_schema} =
        WorkflowMetal.Storage.create_case(
          DummyApplication,
          %Schema.Case.Params{
            workflow_id: workflow_schema.id
          }
        )

      assert {:ok, pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      assert_receive :a_completed
    end

    test "execute a workitem and put an output" do
      {:ok, workflow_schema} =
        SequentialRouting.create(
          DummyApplication,
          a: SequentialRouting.build_echo_transition(1, reply: :a_completed),
          b: SequentialRouting.build_echo_transition(2, reply: :b_completed)
        )

      {:ok, case_schema} =
        WorkflowMetal.Storage.create_case(
          DummyApplication,
          %Schema.Case.Params{
            workflow_id: workflow_schema.id
          }
        )

      assert {:ok, pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      assert_receive :a_completed

      {:ok, workitems} =
        WorkflowMetal.Storage.Adapters.InMemory.list_workitems(DummyApplication, workflow_schema.id)

      workitems
      |> Enum.filter(&(&1.case_id === case_schema.id))
      |> Enum.each(fn workitem ->
        assert workitem.output === %{reply: :a_completed}
      end)
    end
  end
end
