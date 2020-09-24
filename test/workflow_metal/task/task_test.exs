defmodule WorkflowMetal.Task.TaskTest do
  use ExUnit.Case, async: true
  use WorkflowMetal.Support.InMemoryStorageCase

  import WorkflowMetal.Helpers.Wait

  alias WorkflowMetal.Case.Supervisor, as: CaseSupervisor
  alias WorkflowMetal.Storage.Adapters.InMemory, as: InMemoryStorage
  alias WorkflowMetal.Storage.Schema
  alias WorkflowMetal.Support.Workflows.SequentialRouting
  alias WorkflowMetal.Task.Supervisor, as: TaskSupervisor
  alias WorkflowMetal.Workitem.Workitem

  describe "complete_task" do
    test "successfully" do
      {:ok, workflow_schema} = SequentialRouting.create(DummyApplication)

      {:ok, case_schema} = insert_case(DummyApplication, workflow_schema)

      assert {:ok, pid} = CaseSupervisor.open_case(DummyApplication, case_schema.id)

      until(fn ->
        assert_receive :a_completed
      end)

      until(fn ->
        {:ok, tasks} = InMemoryStorage.list_tasks(DummyApplication, workflow_schema.id)

        {:ok, workitem_schemas} =
          InMemoryStorage.list_workitems(DummyApplication, workflow_schema.id)

        assert length(tasks) === 2

        [a_task, b_task] = Enum.filter(tasks, &(&1.case_id === case_schema.id))

        assert a_task.token_payload === %{
                 (workitem_schemas |> Enum.find(&(&1.task_id == a_task.id))).id => %{
                   reply: :a_completed
                 }
               }

        assert b_task.token_payload === %{
                 (workitem_schemas |> Enum.find(&(&1.task_id == b_task.id))).id => %{
                   reply: :b_completed
                 }
               }
      end)
    end
  end

  describe "restore_from_storage" do
    setup do
      {:ok, workflow_schema} = SequentialRouting.create(DummyApplication)

      {:ok, case_schema} = insert_case(DummyApplication, workflow_schema)

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
          %{state: :active}
        )

      {:ok, {start_place, _end_place}} =
        WorkflowMetal.Storage.fetch_edge_places(DummyApplication, workflow_schema.id)

      {:ok, [a_transition]} =
        WorkflowMetal.Storage.fetch_transitions(DummyApplication, start_place.id, :out)

      {:ok, task_schema} =
        WorkflowMetal.Storage.insert_task(
          DummyApplication,
          %Schema.Task{
            id: make_id(),
            state: :started,
            workflow_id: workflow_schema.id,
            case_id: case_schema.id,
            transition_id: a_transition.id
          }
        )

      [a_transition: a_transition, case_schema: case_schema, task_schema: task_schema]
    end

    test "restore from started state", %{case_schema: case_schema, task_schema: task_schema} do
      assert {:ok, pid} = TaskSupervisor.open_task(DummyApplication, task_schema.id)

      until(fn -> assert_receive :a_completed end)
      until(fn -> assert_receive :b_completed end)

      until(fn ->
        {:ok, tasks} = InMemoryStorage.list_tasks(DummyApplication, task_schema.workflow_id)

        {:ok, workitem_schemas} =
          InMemoryStorage.list_workitems(DummyApplication, task_schema.workflow_id)

        assert length(tasks) === 2

        [a_task, b_task] = Enum.filter(tasks, &(&1.case_id === case_schema.id))

        assert a_task.state === :completed
        assert b_task.state === :completed

        assert a_task.token_payload === %{
                 (workitem_schemas |> Enum.find(&(&1.task_id == a_task.id))).id => %{
                   reply: :a_completed
                 }
               }

        assert b_task.token_payload === %{
                 (workitem_schemas |> Enum.find(&(&1.task_id == b_task.id))).id => %{
                   reply: :b_completed
                 }
               }
      end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)
        assert case_schema.state === :finished
      end)
    end

    test "restore from allocated state", %{
      a_transition: a_transition,
      case_schema: case_schema,
      task_schema: task_schema
    } do
      {:ok, task_schema} =
        WorkflowMetal.Storage.update_task(
          DummyApplication,
          task_schema.id,
          %{state: :allocated}
        )

      {:ok, _workitem_schema} =
        WorkflowMetal.Storage.insert_workitem(
          DummyApplication,
          %Schema.Workitem{
            id: make_id(),
            state: :created,
            workflow_id: task_schema.workflow_id,
            transition_id: a_transition.id,
            case_id: case_schema.id,
            task_id: task_schema.id
          }
        )

      assert {:ok, pid} = TaskSupervisor.open_task(DummyApplication, task_schema.id)

      until(fn -> assert_receive :a_completed end)
      until(fn -> assert_receive :b_completed end)

      until(fn ->
        {:ok, tasks} = InMemoryStorage.list_tasks(DummyApplication, task_schema.workflow_id)

        {:ok, workitem_schemas} =
          InMemoryStorage.list_workitems(DummyApplication, task_schema.workflow_id)

        assert length(tasks) === 2

        [a_task, b_task] = Enum.filter(tasks, &(&1.case_id === case_schema.id))

        assert a_task.state === :completed
        assert b_task.state === :completed

        assert a_task.token_payload === %{
                 (workitem_schemas |> Enum.find(&(&1.task_id == a_task.id))).id => %{
                   reply: :a_completed
                 }
               }

        assert b_task.token_payload === %{
                 (workitem_schemas |> Enum.find(&(&1.task_id == b_task.id))).id => %{
                   reply: :b_completed
                 }
               }
      end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)
        assert case_schema.state === :finished
      end)
    end

    test "restore from completed state", %{task_schema: task_schema} do
      assert {:ok, pid} = TaskSupervisor.open_task(DummyApplication, task_schema.id)

      until(fn -> assert_receive :a_completed end)
      until(fn -> assert_receive :b_completed end)

      until(fn ->
        {:ok, tasks} =
          InMemoryStorage.list_tasks(
            DummyApplication,
            task_schema.workflow_id
          )

        assert length(tasks) === 2

        Enum.each(tasks, fn task ->
          assert task.state === :completed

          assert {:error, :task_not_available} =
                   TaskSupervisor.open_task(DummyApplication, task.id)
        end)
      end)
    end

    test "restore from abandoned state", %{task_schema: task_schema} do
      {:ok, task_schema} =
        WorkflowMetal.Storage.update_task(DummyApplication, task_schema.id, %{state: :abandoned})

      assert {:error, :task_not_available} =
               TaskSupervisor.open_task(DummyApplication, task_schema.id)
    end
  end

  describe "restore and request tokens" do
    setup do
      workflow = SequentialRouting.build_workflow()

      {:ok, workflow_schema} =
        SequentialRouting.create(
          DummyApplication,
          workflow,
          a: SequentialRouting.build_asynchronous_transition(workflow, %{reply: :a_completed}),
          b: SequentialRouting.build_echo_transition(workflow, %{reply: :b_completed})
        )

      {:ok, case_schema} = insert_case(DummyApplication, workflow_schema)

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
          %{state: :active}
        )

      {:ok, {start_place, _end_place}} =
        WorkflowMetal.Storage.fetch_edge_places(DummyApplication, workflow_schema.id)

      {:ok, [a_transition]} =
        WorkflowMetal.Storage.fetch_transitions(DummyApplication, start_place.id, :out)

      {:ok, task_schema} =
        WorkflowMetal.Storage.insert_task(
          DummyApplication,
          %Schema.Task{
            id: make_id(),
            state: :started,
            workflow_id: workflow_schema.id,
            case_id: case_schema.id,
            transition_id: a_transition.id
          }
        )

      [
        a_transition: a_transition,
        genesis_token: genesis_token,
        case_schema: case_schema,
        task_schema: task_schema
      ]
    end

    test "restore from executing state", %{
      a_transition: a_transition,
      genesis_token: genesis_token,
      case_schema: case_schema,
      task_schema: task_schema
    } do
      {:ok, task_schema} =
        WorkflowMetal.Storage.update_task(
          DummyApplication,
          task_schema.id,
          %{state: :allocated}
        )

      {:ok, workitem_schema} =
        WorkflowMetal.Storage.insert_workitem(
          DummyApplication,
          %Schema.Workitem{
            id: make_id(),
            state: :created,
            workflow_id: task_schema.workflow_id,
            transition_id: a_transition.id,
            case_id: case_schema.id,
            task_id: task_schema.id
          }
        )

      {:ok, _} =
        WorkflowMetal.Storage.lock_tokens(DummyApplication, [genesis_token.id], task_schema.id)

      {:ok, task_schema} =
        WorkflowMetal.Storage.update_task(
          DummyApplication,
          task_schema.id,
          %{state: :executing}
        )

      assert {:ok, pid} = TaskSupervisor.open_task(DummyApplication, task_schema.id)

      until(fn -> assert_receive :a_completed end)

      workitem_server = Workitem.via_name(DummyApplication, workitem_schema)

      :ok = Workitem.complete(workitem_server, %{reply: :a_completed})

      until(fn -> assert_receive :b_completed end)

      until(fn ->
        {:ok, tasks} = InMemoryStorage.list_tasks(DummyApplication, task_schema.workflow_id)

        {:ok, workitem_schemas} =
          InMemoryStorage.list_workitems(DummyApplication, task_schema.workflow_id)

        assert length(tasks) === 2

        [a_task, b_task] = Enum.filter(tasks, &(&1.case_id === case_schema.id))

        assert a_task.state === :completed
        assert b_task.state === :completed

        assert a_task.token_payload === %{
                 (workitem_schemas |> Enum.find(&(&1.task_id == a_task.id))).id => %{
                   reply: :a_completed
                 }
               }

        assert b_task.token_payload === %{
                 (workitem_schemas |> Enum.find(&(&1.task_id == b_task.id))).id => %{
                   reply: :b_completed
                 }
               }
      end)

      until(fn ->
        {:ok, case_schema} = WorkflowMetal.Storage.fetch_case(DummyApplication, case_schema.id)
        assert case_schema.state === :finished
      end)
    end
  end

  defp make_id, do: :erlang.unique_integer([:positive, :monotonic])
end
