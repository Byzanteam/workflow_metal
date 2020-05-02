defmodule WorkflowMetal.Workitem.WorkitemTest do
  use ExUnit.Case, async: true
  use WorkflowMetal.Support.InMemoryStorageCase

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

  describe "execute_workitem" do
    test "execute successfully" do
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
    end

    defmodule AsynchronousTransition do
      use WorkflowMetal.Executor

      @impl true
      def execute(workitem, options) do
        {:ok, _tokens} = preexecute(options[:application], workitem)

        executor_params = Keyword.fetch!(options, :executor_params)
        request = Keyword.fetch!(executor_params, :request)
        reply = Keyword.fetch!(executor_params, :reply)

        send(request, reply)

        :started
      end
    end

    test "execute successfully and asynchronously" do
      alias WorkflowMetal.Workitem.Workitem

      {:ok, workflow_schema} =
        SequentialRouting.create(
          DummyApplication,
          a:
            SequentialRouting.build_transition(1, AsynchronousTransition,
              request: self(),
              reply: :workitem_started
            ),
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
        assert_receive :workitem_started
      end)

      workitem =
        until(fn ->
          {:ok, workitems} = InMemoryStorage.list_workitems(DummyApplication, workflow_schema.id)
          [workitem | _rest] = Enum.filter(workitems, &(&1.case_id === case_schema.id))

          assert workitem.state === :started

          workitem
        end)

      output = %{reply: :asynchronous_reply}

      workitem_name = Workitem.name(workitem)

      workitem_server = WorkflowMetal.Registration.via_tuple(DummyApplication, workitem_name)
      Workitem.complete(workitem_server, output)

      until(fn ->
        {:ok, workitems} = InMemoryStorage.list_workitems(DummyApplication, workflow_schema.id)
        [workitem | _rest] = Enum.filter(workitems, &(&1.case_id === case_schema.id))

        assert workitem.state === :completed
        assert workitem.output === output
      end)
    end

    test "put an output" do
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
        {:ok, workitems} = InMemoryStorage.list_workitems(DummyApplication, workflow_schema.id)
        [workitem | _rest] = Enum.filter(workitems, &(&1.case_id === case_schema.id))

        assert workitem.output === %{reply: :a_completed}
      end)
    end

    defmodule TwiceLockTransition do
      use WorkflowMetal.Executor

      @impl true
      def execute(workitem, options) do
        {:ok, _tokens} = preexecute(options[:application], workitem)
        {:ok, _tokens} = preexecute(options[:application], workitem)

        executor_params = Keyword.fetch!(options, :executor_params)
        request = Keyword.fetch!(executor_params, :request)
        reply = Keyword.fetch!(executor_params, :reply)

        send(request, reply)

        {:completed, %{reply: reply}}
      end
    end

    test "lock tokens twice" do
      {:ok, workflow_schema} =
        SequentialRouting.create(
          DummyApplication,
          a:
            SequentialRouting.build_transition(1, TwiceLockTransition,
              request: self(),
              reply: :locked_twice
            ),
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
        assert_receive :locked_twice
      end)

      until(fn ->
        {:ok, workitems} = InMemoryStorage.list_workitems(DummyApplication, workflow_schema.id)
        [workitem | _rest] = Enum.filter(workitems, &(&1.case_id === case_schema.id))

        assert workitem.output === %{reply: :locked_twice}
      end)
    end
  end

  describe "complete" do
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

      {:ok, task_schema} =
        WorkflowMetal.Storage.create_task(
          DummyApplication,
          %Schema.Task.Params{
            workflow_id: workflow_schema.id,
            case_id: case_schema.id,
            transition_id: a_transition.id
          }
        )

      {:ok, task_schema} =
        WorkflowMetal.Storage.update_task(
          DummyApplication,
          task_schema.id,
          :allocated
        )

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

      [workitem_schema: workitem_schema]
    end

    test "cannt complete a created workitem", %{workitem_schema: workitem_schema} do
      {:error, :workitem_not_available} =
        WorkflowMetal.Workitem.Supervisor.complete_workitem(
          DummyApplication,
          workitem_schema.id,
          :a_completed
        )
    end

    test "complete a started workitem", %{workitem_schema: workitem_schema} do
      WorkflowMetal.Storage.update_workitem(DummyApplication, workitem_schema.id, :started)

      :ok =
        WorkflowMetal.Workitem.Supervisor.complete_workitem(
          DummyApplication,
          workitem_schema.id,
          :a_completed
        )

      {:ok, workitem_schema} =
        WorkflowMetal.Storage.fetch_workitem(DummyApplication, workitem_schema.id)

      assert workitem_schema.state === :completed
    end

    test "cant complete a completed workitem", %{workitem_schema: workitem_schema} do
      WorkflowMetal.Storage.update_workitem(
        DummyApplication,
        workitem_schema.id,
        {:completed, nil}
      )

      {:error, :workitem_not_available} =
        WorkflowMetal.Workitem.Supervisor.complete_workitem(
          DummyApplication,
          workitem_schema.id,
          :a_completed
        )
    end

    test "cant complete a abandoned workitem", %{workitem_schema: workitem_schema} do
      WorkflowMetal.Storage.update_workitem(
        DummyApplication,
        workitem_schema.id,
        :abandoned
      )

      {:error, :workitem_not_available} =
        WorkflowMetal.Workitem.Supervisor.complete_workitem(
          DummyApplication,
          workitem_schema.id,
          :a_completed
        )
    end
  end

  describe "abandon" do
    setup do
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

      {:ok, task_schema} =
        WorkflowMetal.Storage.create_task(
          DummyApplication,
          %Schema.Task.Params{
            workflow_id: workflow_schema.id,
            case_id: case_schema.id,
            transition_id: a_transition.id
          }
        )

      {:ok, task_schema} =
        WorkflowMetal.Storage.update_task(
          DummyApplication,
          task_schema.id,
          :allocated
        )

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

      [workitem_schema: workitem_schema]
    end

    test "can abandon a started workitem", %{workitem_schema: workitem_schema} do
      {:ok, workitem_schema} =
        WorkflowMetal.Storage.update_workitem(DummyApplication, workitem_schema.id, :started)

      :ok =
        WorkflowMetal.Workitem.Supervisor.abandon_workitem(
          DummyApplication,
          workitem_schema.id
        )

      until(fn ->
        {:ok, workitem_schema} =
          WorkflowMetal.Storage.fetch_workitem(DummyApplication, workitem_schema.id)

        assert workitem_schema.state === :abandoned
      end)
    end

    test "can abandon a running started workitem", %{workitem_schema: workitem_schema} do
      {:ok, workitem_schema} =
        WorkflowMetal.Storage.update_workitem(DummyApplication, workitem_schema.id, :started)

      {:ok, pid} =
        WorkflowMetal.Workitem.Supervisor.open_workitem(
          DummyApplication,
          workitem_schema.id
        )

      :ok =
        WorkflowMetal.Workitem.Supervisor.abandon_workitem(
          DummyApplication,
          workitem_schema.id
        )

      until(fn -> refute Process.alive?(pid) end)

      until(fn ->
        {:ok, workitem_schema} =
          WorkflowMetal.Storage.fetch_workitem(DummyApplication, workitem_schema.id)

        assert workitem_schema.state === :abandoned
      end)
    end

    test "cant abandon a completed workitem", %{workitem_schema: workitem_schema} do
      WorkflowMetal.Storage.update_workitem(
        DummyApplication,
        workitem_schema.id,
        {:completed, nil}
      )

      {:error, :workitem_not_available} =
        WorkflowMetal.Workitem.Supervisor.abandon_workitem(
          DummyApplication,
          workitem_schema.id
        )
    end

    test "can abandon a abandoned workitem", %{workitem_schema: workitem_schema} do
      WorkflowMetal.Storage.update_workitem(
        DummyApplication,
        workitem_schema.id,
        :abandoned
      )

      {:error, :workitem_not_available} =
        WorkflowMetal.Workitem.Supervisor.abandon_workitem(
          DummyApplication,
          workitem_schema.id
        )
    end
  end

  describe "restore" do
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

      {:ok, task_schema} =
        WorkflowMetal.Storage.create_task(
          DummyApplication,
          %Schema.Task.Params{
            workflow_id: workflow_schema.id,
            case_id: case_schema.id,
            transition_id: a_transition.id
          }
        )

      {:ok, task_schema} =
        WorkflowMetal.Storage.update_task(
          DummyApplication,
          task_schema.id,
          :allocated
        )

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

      [workitem_schema: workitem_schema]
    end

    test "from created", %{workitem_schema: workitem_schema} do
      {:ok, _} =
        WorkflowMetal.Workitem.Supervisor.open_workitem(DummyApplication, workitem_schema.id)

      until(fn -> assert_receive :a_completed end)
      until(fn -> assert_receive :b_completed end)
    end

    test "from started", %{workitem_schema: workitem_schema} do
      {:ok, workitem_schema} =
        WorkflowMetal.Storage.update_workitem(DummyApplication, workitem_schema.id, :started)

      {:ok, _pid} =
        WorkflowMetal.Workitem.Supervisor.open_workitem(DummyApplication, workitem_schema.id)

      refute_receive :a_completed
    end

    test "from completed", %{workitem_schema: workitem_schema} do
      {:ok, workitem_schema} =
        WorkflowMetal.Storage.update_workitem(
          DummyApplication,
          workitem_schema.id,
          {:completed, nil}
        )

      assert {:error, :workitem_not_available} =
               WorkflowMetal.Workitem.Supervisor.open_workitem(
                 DummyApplication,
                 workitem_schema.id
               )
    end

    test "from abandoned", %{workitem_schema: workitem_schema} do
      {:ok, workitem_schema} =
        WorkflowMetal.Storage.update_workitem(DummyApplication, workitem_schema.id, :abandoned)

      assert {:error, :workitem_not_available} =
               WorkflowMetal.Workitem.Supervisor.open_workitem(
                 DummyApplication,
                 workitem_schema.id
               )
    end
  end
end
