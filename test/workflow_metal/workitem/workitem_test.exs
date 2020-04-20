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
        {:ok, _tokens} = lock_tokens(options[:application], workitem)

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
        {:ok, _tokens} = lock_tokens(options[:application], workitem)
        {:ok, _tokens} = lock_tokens(options[:application], workitem)

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
end
