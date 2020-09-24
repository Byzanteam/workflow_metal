defmodule WorkflowMetal.Support.Workflows.SequentialRouting do
  @moduledoc false

  alias WorkflowMetal.Storage.Schema

  defmodule SimpleTransition do
    @moduledoc false

    use WorkflowMetal.Executor

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      {:ok, _tokens} = preexecute(options[:application], workitem)

      {:completed, :ok}
    end
  end

  defmodule EchoTransition do
    @moduledoc false

    use WorkflowMetal.Executor

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      {:ok, _tokens} = preexecute(options[:application], workitem)

      executor_params = Keyword.fetch!(options, :executor_params)

      request = Map.fetch!(executor_params, :request)
      reply = Map.fetch!(executor_params, :reply)

      send(request, reply)

      {:completed, %{reply: reply}}
    end
  end

  defmodule AsynchronousTransition do
    @moduledoc false

    use WorkflowMetal.Executor

    @impl true
    def execute(_workitem, options) do
      executor_params = Keyword.fetch!(options, :executor_params)

      request = Map.fetch!(executor_params, :request)
      reply = Map.fetch!(executor_params, :reply)

      send(request, reply)

      :started
    end

    @impl WorkflowMetal.Executor
    def abandon(%Schema.Workitem{}, options) do
      executor_params = Keyword.fetch!(options, :executor_params)

      request = Map.fetch!(executor_params, :request)
      reply = Map.fetch!(executor_params, :abandon_reply)

      send(request, reply)

      :ok
    end
  end

  @doc false
  def create(application) do
    workflow = build_workflow()

    workflow_associations_params =
      build_workflow_associations_params(workflow, [
        build_place(workflow, :start),
        build_echo_transition(workflow, %{reply: :a_completed}),
        build_place(workflow, :normal),
        build_echo_transition(workflow, %{reply: :b_completed}),
        build_place(workflow, :end)
      ])

    WorkflowMetal.Storage.insert_workflow(
      application,
      workflow,
      workflow_associations_params
    )
  end

  @doc false
  def create(application, workflow, transitions) do
    workflow_associations_params =
      build_workflow_associations_params(workflow, [
        build_place(workflow, :start),
        Keyword.get_lazy(transitions, :a, fn ->
          build_echo_transition(workflow, %{reply: :a_completed})
        end),
        build_place(workflow, :normal),
        Keyword.get_lazy(transitions, :b, fn ->
          build_echo_transition(workflow, %{reply: :b_completed})
        end),
        build_place(workflow, :end)
      ])

    WorkflowMetal.Storage.insert_workflow(
      application,
      workflow,
      workflow_associations_params
    )
  end

  @doc false
  def build_workflow do
    %Schema.Workflow{
      id: make_id(),
      state: :active
    }
  end

  @doc false
  def build_workflow_associations_params(
        %Schema.Workflow{} = workflow_schema,
        [first | rest] = nodes
      ) do
    {_, arcs} =
      Enum.reduce(rest, {first, []}, fn
        %Schema.Place{} = to, {%Schema.Transition{} = from, arcs} ->
          {to,
           [
             %Schema.Arc{
               id: make_id(),
               place_id: to.id,
               transition_id: from.id,
               direction: :in,
               workflow_id: workflow_schema.id
             }
             | arcs
           ]}

        %Schema.Transition{} = to, {%Schema.Place{} = from, arcs} ->
          {to,
           [
             %Schema.Arc{
               id: make_id(),
               place_id: from.id,
               transition_id: to.id,
               direction: :out,
               workflow_id: workflow_schema.id
             }
             | arcs
           ]}
      end)

    {places, transitions} =
      Enum.split_with(nodes, fn
        %Schema.Place{} -> true
        %Schema.Transition{} -> false
      end)

    %{
      places: places,
      transitions: transitions,
      arcs: arcs
    }
  end

  @doc false
  def build_place(%Schema.Workflow{id: workflow_id}, place_type) do
    %Schema.Place{id: make_id(), type: place_type, workflow_id: workflow_id}
  end

  @doc false
  def build_simple_transition(%Schema.Workflow{id: workflow_id}) do
    struct(
      Schema.Transition,
      %{
        id: make_id(),
        join_type: :none,
        split_type: :none,
        executor: SimpleTransition,
        workflow_id: workflow_id
      }
    )
  end

  @doc false
  def build_echo_transition(%Schema.Workflow{id: workflow_id}, executor_params) do
    struct(
      Schema.Transition,
      %{
        id: make_id(),
        join_type: :none,
        split_type: :none,
        executor: EchoTransition,
        executor_params: Map.put_new(executor_params, :request, self()),
        workflow_id: workflow_id
      }
    )
  end

  @doc false
  def build_asynchronous_transition(%Schema.Workflow{id: workflow_id}, executor_params) do
    struct(
      Schema.Transition,
      %{
        id: make_id(),
        join_type: :none,
        split_type: :none,
        executor: AsynchronousTransition,
        executor_params: Map.put_new(executor_params, :request, self()),
        workflow_id: workflow_id
      }
    )
  end

  @doc false
  def build_transition(%Schema.Workflow{id: workflow_id}, params) do
    struct(
      Schema.Transition,
      Map.merge(
        %{
          id: make_id(),
          join_type: :none,
          split_type: :none,
          workflow_id: workflow_id
        },
        params
      )
    )
  end

  defp make_id, do: :erlang.unique_integer([:positive, :monotonic])
end
