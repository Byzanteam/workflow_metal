defmodule WorkflowMetal.Case.CaseTest do
  use ExUnit.Case, async: true
  use WorkflowMetal.Support.InMemoryStorageCase

  import WorkflowMetal.Helpers.Wait

  defmodule DummyApplication do
    use WorkflowMetal.Application,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  alias WorkflowMetal.Application.WorkflowsSupervisor
  alias WorkflowMetal.Case.Supervisor, as: CaseSupervisor
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

      until(fn ->
        assert_receive :a_completed
      end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)

        assert case_schema.state === :active
      end)
    end
  end

  describe "terminate" do
    test "terminate a case successfully" do
      {:ok, workflow_schema} =
        SequentialRouting.create(
          DummyApplication,
          a:
            SequentialRouting.build_echo_transition(1,
              reply: :a_completed
            ),
          b:
            SequentialRouting.build_asynchronous_transition(2,
              reply: :b_reply,
              abandon_reply: :b_abandoned
            )
        )

      {:ok, case_schema} =
        WorkflowMetal.Storage.create_case(
          DummyApplication,
          %Schema.Case.Params{
            workflow_id: workflow_schema.id
          }
        )

      assert {:ok, _case_server} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      assert_receive :a_completed
      assert_receive :b_reply

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)

        assert case_schema.state === :active
      end)

      assert :ok = CaseSupervisor.terminate_case(DummyApplication, case_schema.id)

      assert_receive :b_abandoned

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)

        assert case_schema.state === :terminated
      end)

      {:ok, {_start_place, end_place}} =
        WorkflowMetal.Storage.fetch_edge_places(DummyApplication, workflow_schema.id)

      {:ok, [b_transition]} =
        WorkflowMetal.Storage.fetch_transitions(DummyApplication, end_place.id, :in)

      {:ok, [task_schema]} =
        WorkflowMetal.Storage.fetch_tasks(DummyApplication, case_schema.id,
          transition_id: b_transition.id
        )

      assert task_schema.state === :abandoned
    end
  end

  describe "finish_case" do
    test "finish a case successfully" do
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
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)

        assert case_schema.state === :finished
      end)
    end
  end

  describe "restore_from_storage" do
    setup do
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

      {:ok, _genesis_token} =
        generate_genesis_token(
          DummyApplication,
          workflow_schema,
          case_schema
        )

      {:ok, case_schema} =
        WorkflowMetal.Storage.update_case(
          DummyApplication,
          case_schema.id,
          :active
        )

      {:ok, {start_place, _end_place}} =
        WorkflowMetal.Storage.fetch_edge_places(DummyApplication, workflow_schema.id)

      {:ok, [a_transition]} =
        WorkflowMetal.Storage.fetch_transitions(DummyApplication, start_place.id, :out)

      [a_transition: a_transition, case_schema: case_schema]
    end

    test "restore from created state", %{case_schema: case_schema} do
      assert {:ok, pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      until(fn -> assert_receive :a_completed end)
      until(fn -> assert_receive :b_completed end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)

        assert case_schema.state === :active
      end)
    end

    test "restore from active state", %{a_transition: a_transition, case_schema: case_schema} do
      {:ok, _task_schema} =
        WorkflowMetal.Storage.create_task(
          DummyApplication,
          %Schema.Task.Params{
            workflow_id: case_schema.workflow_id,
            case_id: case_schema.id,
            transition_id: a_transition.id
          }
        )

      WorkflowMetal.Storage.update_case(DummyApplication, case_schema.id, :active)

      {:ok, _pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      until(fn -> assert_receive :a_completed end)
      until(fn -> assert_receive :b_completed end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)
        assert case_schema.state === :finished
      end)
    end

    test "restore from terminated state", %{case_schema: case_schema} do
      {:ok, case_schema} =
        WorkflowMetal.Storage.update_case(
          DummyApplication,
          case_schema.id,
          :terminated
        )

      assert {:error, :case_not_available} =
               CaseSupervisor.open_case(DummyApplication, case_schema.id)
    end

    test "restore from finished state", %{case_schema: case_schema} do
      assert {:ok, pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      until(fn -> assert_receive :a_completed end)

      until(fn -> assert_receive :b_completed end)

      until(fn -> refute Process.alive?(pid) end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)

        assert case_schema.state === :finished
      end)

      until(fn -> refute Process.alive?(pid) end)

      assert {:error, :case_not_available} =
               CaseSupervisor.open_case(DummyApplication, case_schema.id)
    end
  end
end
