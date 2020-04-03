defmodule WorkflowMetal.Task.TaskTest do
  use ExUnit.Case, async: true

  import WorkflowMetal.Helpers.Wait

  alias WorkflowMetal.Application.WorkflowsSupervisor
  alias WorkflowMetal.Case.Supervisor, as: CaseSupervisor
  alias WorkflowMetal.Storage.Adapters.InMemory, as: InMemoryStorage
  alias WorkflowMetal.Storage.Schema
  alias WorkflowMetal.Support.Workflows.SequentialRouting

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      storage: InMemoryStorage
  end

  setup_all do
    start_supervised!(DummyApplication)

    [application: DummyApplication]
  end

  describe "complete_task" do
    test "successfully" do
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

      until(fn ->
        assert_receive :a_completed
      end)

      until(fn ->
        {:ok, tasks} = InMemoryStorage.list_tasks(DummyApplication, workflow_schema.id)

        tasks
        |> Enum.filter(&(&1.case_id === case_schema.id))
        |> Enum.each(fn task ->
          assert task.token_payload === [%{reply: :a_completed}]
        end)
      end)
    end
  end
end