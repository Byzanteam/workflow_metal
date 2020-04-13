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
    test "restore from created state" do
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

      assert case_schema.state === :created

      assert {:ok, pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      until(fn ->
        assert_receive :a_completed
      end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)

        assert case_schema.state === :active
      end)
    end

    test "restore from active state" do
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

      {:ok, _token} =
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

      {:ok, _pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      until(fn ->
        assert_receive :a_completed
      end)

      until(fn ->
        assert_receive :b_completed
      end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)
        assert case_schema.state === :finished
      end)
    end

    test "restore from canceled state" do
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

      {:ok, case_schema} =
        WorkflowMetal.Storage.update_case(
          DummyApplication,
          case_schema.id,
          :canceled
        )

      assert {:error, :normal} = CaseSupervisor.open_case(DummyApplication, case_schema.id)
    end

    test "restore from finished state" do
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

      assert case_schema.state === :created

      assert {:ok, pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      until(fn ->
        assert_receive :a_completed
      end)

      until(fn ->
        assert_receive :b_completed
      end)

      assert Process.alive?(pid)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)

        assert case_schema.state === :finished
      end)

      until(fn ->
        refute Process.alive?(pid)
      end)

      assert {:error, :normal} = CaseSupervisor.open_case(DummyApplication, case_schema.id)
    end
  end
end
