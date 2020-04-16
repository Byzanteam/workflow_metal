defmodule WorkflowMetal.Task.TaskTest do
  use ExUnit.Case, async: true
  use WorkflowMetal.Support.InMemoryStorageCase

  import WorkflowMetal.Helpers.Wait

  alias WorkflowMetal.Application.WorkflowsSupervisor
  alias WorkflowMetal.Case.Supervisor, as: CaseSupervisor
  alias WorkflowMetal.Storage.Adapters.InMemory, as: InMemoryStorage
  alias WorkflowMetal.Storage.Schema
  alias WorkflowMetal.Support.Workflows.SequentialRouting
  alias WorkflowMetal.Task.Supervisor, as: TaskSupervisor
  alias WorkflowMetal.Workitem.Workitem

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

        assert length(tasks) === 2

        [a_task, b_task] = Enum.filter(tasks, &(&1.case_id === case_schema.id))

        assert a_task.token_payload === [%{reply: :a_completed}]
        assert b_task.token_payload === [%{reply: :b_completed}]
      end)
    end
  end

  describe "restore_from_storage" do
    test "restore from started state" do
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

      {:ok, {start_place, _end_place}} =
        WorkflowMetal.Storage.fetch_edge_places(DummyApplication, workflow_schema.id)

      {:ok, [a_transition]} =
        WorkflowMetal.Storage.fetch_transitions(DummyApplication, start_place.id, :out)

      task_params = %Schema.Task.Params{
        workflow_id: workflow_schema.id,
        case_id: case_schema.id,
        transition_id: a_transition.id
      }

      {:ok, task_schema} = WorkflowMetal.Storage.create_task(DummyApplication, task_params)

      assert {:ok, pid} = TaskSupervisor.open_task(DummyApplication, task_schema.id)

      until(fn ->
        assert_receive :a_completed
      end)

      until(fn ->
        assert_receive :b_completed
      end)

      until(fn ->
        {:ok, tasks} = InMemoryStorage.list_tasks(DummyApplication, workflow_schema.id)

        assert length(tasks) === 2

        [a_task, b_task] = Enum.filter(tasks, &(&1.case_id === case_schema.id))

        assert a_task.state === :completed
        assert a_task.token_payload === [%{reply: :a_completed}]

        assert b_task.state === :completed
        assert b_task.token_payload === [%{reply: :b_completed}]
      end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)
        assert case_schema.state === :finished
      end)
    end

    test "restore from started state and request free tokens from the case" do
      {:ok, workflow_schema} =
        SequentialRouting.create(
          DummyApplication,
          a: SequentialRouting.build_asynchronous_transition(1, reply: :a_completed),
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

      task_params = %Schema.Task.Params{
        workflow_id: workflow_schema.id,
        case_id: case_schema.id,
        transition_id: a_transition.id
      }

      {:ok, task_schema} = WorkflowMetal.Storage.create_task(DummyApplication, task_params)

      refute_receive :a_completed

      assert {:ok, pid} = TaskSupervisor.open_task(DummyApplication, task_schema.id)

      until(fn ->
        assert_receive :a_completed
      end)

      :ok = GenStateMachine.stop(pid)

      {:ok, [workitem]} = WorkflowMetal.Storage.fetch_workitems(DummyApplication, task_schema.id)

      {:ok, _workitem_schema} =
        WorkflowMetal.Storage.update_workitem(
          DummyApplication,
          workitem.id,
          :abandoned
        )

      assert {:ok, pid} = TaskSupervisor.open_task(DummyApplication, task_schema.id)

      until(fn ->
        assert_receive :a_completed
      end)

      WorkflowMetal.Task.Task.lock_tokens(
        WorkflowMetal.Task.Task.via_name(DummyApplication, task_schema)
      )

      [workitem] =
        WorkflowMetal.Storage.fetch_workitems(
          DummyApplication,
          task_schema.id
        )
        |> elem(1)
        |> Enum.filter(&(&1.state === :started))

      {:ok, _pid} =
        WorkflowMetal.Workitem.Supervisor.open_workitem(
          DummyApplication,
          workitem.id
        )

      :ok =
        Workitem.complete(
          Workitem.via_name(DummyApplication, workitem),
          %{reply: :a_completed}
        )

      until(fn ->
        assert_receive :b_completed
      end)

      until(fn ->
        {:ok, tasks} = InMemoryStorage.list_tasks(DummyApplication, workflow_schema.id)

        assert length(tasks) === 2

        [a_task, b_task] = Enum.filter(tasks, &(&1.case_id === case_schema.id))

        assert a_task.state === :completed
        assert a_task.token_payload === [%{reply: :a_completed}]

        assert b_task.state === :completed
        assert b_task.token_payload === [%{reply: :b_completed}]
      end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)
        assert case_schema.state === :finished
      end)
    end

    test "restore from executing state" do
      {:ok, workflow_schema} =
        SequentialRouting.create(
          DummyApplication,
          a: SequentialRouting.build_asynchronous_transition(1, reply: :a_completed),
          b: SequentialRouting.build_echo_transition(2, reply: :b_completed)
        )

      {:ok, case_schema} =
        WorkflowMetal.Storage.create_case(
          DummyApplication,
          %Schema.Case.Params{
            workflow_id: workflow_schema.id
          }
        )

      {:ok, genesis_token} =
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

      task_params = %Schema.Task.Params{
        workflow_id: workflow_schema.id,
        case_id: case_schema.id,
        transition_id: a_transition.id
      }

      {:ok, task_schema} = WorkflowMetal.Storage.create_task(DummyApplication, task_params)

      # lock tokens
      {:ok, _token_schema} =
        WorkflowMetal.Storage.lock_tokens(
          DummyApplication,
          [genesis_token.id],
          task_schema.id
        )

      # generate workitem
      {:ok, workitem_schema} =
        WorkflowMetal.Storage.create_workitem(
          DummyApplication,
          %Schema.Workitem.Params{
            workflow_id: workflow_schema.id,
            transition_id: a_transition.id,
            case_id: case_schema.id,
            task_id: task_schema.id
          }
        )

      # mark the task executing
      {:ok, task_schema} =
        WorkflowMetal.Storage.update_task(
          DummyApplication,
          task_schema.id,
          :executing
        )

      refute_receive :a_completed

      assert {:ok, pid} = TaskSupervisor.open_task(DummyApplication, task_schema.id)

      until(fn ->
        assert_receive :a_completed
      end)

      workitem_server = Workitem.via_name(DummyApplication, workitem_schema)

      :ok = Workitem.complete(workitem_server, %{reply: :a_completed})

      until(fn ->
        assert_receive :b_completed
      end)

      until(fn ->
        {:ok, tasks} = InMemoryStorage.list_tasks(DummyApplication, workflow_schema.id)

        assert length(tasks) === 2

        [a_task, b_task] = Enum.filter(tasks, &(&1.case_id === case_schema.id))

        assert a_task.state === :completed
        assert a_task.token_payload === [%{reply: :a_completed}]

        assert b_task.state === :completed
        assert b_task.token_payload === [%{reply: :b_completed}]
      end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)
        assert case_schema.state === :finished
      end)
    end

    test "restore from completed state" do
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
        assert_receive :b_completed
      end)

      until(fn ->
        {:ok, [a_task | _]} =
          InMemoryStorage.list_tasks(
            DummyApplication,
            workflow_schema.id
          )

        assert a_task.state === :completed
        assert {:error, :normal} = TaskSupervisor.open_task(DummyApplication, a_task.id)
      end)
    end

    test "restore from abandoned state" do
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

      {:ok, {start_place, _end_place}} =
        WorkflowMetal.Storage.fetch_edge_places(DummyApplication, workflow_schema.id)

      {:ok, [a_transition]} =
        WorkflowMetal.Storage.fetch_transitions(DummyApplication, start_place.id, :out)

      task_params = %Schema.Task.Params{
        workflow_id: workflow_schema.id,
        case_id: case_schema.id,
        transition_id: a_transition.id
      }

      {:ok, task_schema} = WorkflowMetal.Storage.create_task(DummyApplication, task_params)

      {:ok, task_schema} =
        WorkflowMetal.Storage.update_task(DummyApplication, task_schema.id, :abandoned)

      assert {:error, :normal} = TaskSupervisor.open_task(DummyApplication, task_schema.id)
    end
  end
end
