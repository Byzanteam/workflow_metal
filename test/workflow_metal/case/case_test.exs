defmodule WorkflowMetal.Case.CaseTest do
  use ExUnit.Case, async: true

  import WorkflowMetal.Helpers.Wait

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
    defmodule ATransition do
      @moduledoc false

      @behaviour WorkflowMetal.Executor

      @impl WorkflowMetal.Executor
      def execute(%Schema.Workitem{}, _tokens, _options) do
        {:completed, %{}}
      end

      @impl WorkflowMetal.Executor
      def build_token_payload(workitems, _options) do
        {:ok, Enum.map(workitems, & &1.output)}
      end
    end

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
end
