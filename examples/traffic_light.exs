alias WorkflowMetal.Storage.Schema

# Traffic light
#
# +------+                    +-----+                      +----------+
# | init +---->(yellow)+----->+ y2r +------>(red)+-------->+ will_end |
# +---+--+         ^          +-----+         +            +-----+----+
#     ^            |                          |                  |
#     |            |                          v                  |
#     +         +--+--+                    +--+--+               v
#  (start)      | g2y +<----+(green)<------+ r2g |             (end)
#               +-----+                    +-----+

defmodule TrafficLight do
  @moduledoc false

  defmodule Workflow do
    use WorkflowMetal.Application,
      registry: WorkflowMetal.Registration.LocalRegistry,
      storage: WorkflowMetal.Storage.Adapters.InMemory
  end

  defmodule Init do
    @moduledoc false

    use WorkflowMetal.Executor

    alias WorkflowMetal.Storage.Schema

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      {:ok, _tokens} = lock_tokens(workitem, options)

      IO.puts("\n#{TrafficLight.now()} the light is on.")

      {:completed, :inited}
    end
  end

  defmodule Y2R do
    @moduledoc false

    use WorkflowMetal.Executor

    alias WorkflowMetal.Storage.Schema

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      IO.puts("\n#{TrafficLight.now()} the light is about to turning red in 1s.")

      Task.start(__MODULE__, :run, [workitem, options])
      :started
    end

    def run(%Schema.Workitem{} = workitem, options) do
      Process.sleep(1000)

      {:ok, _tokens} = lock_tokens(workitem, options)

      TrafficLight.complete_workitem(workitem, options, :turn_red)

      TrafficLight.log_light(:red)
    end
  end

  defmodule R2G do
    @moduledoc false

    use WorkflowMetal.Executor

    alias WorkflowMetal.Storage.Schema

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      IO.puts("\n#{TrafficLight.now()} the light is about to turning green in 5s.")

      Task.start(__MODULE__, :run, [workitem, options])
      :started
    end

    def run(%Schema.Workitem{} = workitem, options) do
      Process.sleep(5000)

      case lock_tokens(workitem, options) do
        {:ok, _tokens} ->
          TrafficLight.complete_workitem(workitem, options, :turn_green)

          TrafficLight.log_light(:green)

        _ ->
          :skip
      end
    end
  end

  defmodule G2Y do
    @moduledoc false

    use WorkflowMetal.Executor

    alias WorkflowMetal.Storage.Schema

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      IO.puts("\n#{TrafficLight.now()} the light is about to turning yellow in 4s.")

      Task.start(__MODULE__, :run, [workitem, options])
      :started
    end

    def run(%Schema.Workitem{} = workitem, options) do
      Process.sleep(4000)

      {:ok, _tokens} = lock_tokens(workitem, options)

      TrafficLight.complete_workitem(workitem, options, :turn_yellow)

      TrafficLight.log_light(:yellow)
    end
  end

  defmodule WillEnd do
    @moduledoc false

    use WorkflowMetal.Executor

    alias WorkflowMetal.Storage.Schema

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      # 50% chance
      if :rand.uniform(10) <= 5 do
        case lock_tokens(workitem, options) do
          {:ok, _tokens} ->
            IO.puts("\n#{TrafficLight.now()} the light is off.")

            {:completed, :ended}

          _ ->
            :abandoned
        end
      else
        :abandoned
      end
    end
  end

  def complete_workitem(workitem, options, output) do
    WorkflowMetal.Workitem.Workitem.complete(
      workitem_server(workitem, options),
      output
    )
  end

  defp workitem_server(workitem, options) do
    application = Keyword.fetch!(options, :application)

    WorkflowMetal.Workitem.Workitem.via_name(
      application,
      workitem
    )
  end

  def now do
    DateTime.utc_now() |> DateTime.to_string()
  end

  def log_light(color) do
    IO.puts([
      "\n",
      now(),
      " the light is ",
      apply(IO.ANSI, color, []),
      to_string(color),
      IO.ANSI.reset(),
      "."
    ])
  end
end

{:ok, _pid} = TrafficLight.Workflow.start_link()

{:ok, traffic_light_workflow} =
  WorkflowMetal.Storage.create_workflow(
    TrafficLight.Workflow,
    %Schema.Workflow.Params{
      places: [
        %Schema.Place.Params{rid: :start, type: :start},
        %Schema.Place.Params{rid: :yellow, type: :normal},
        %Schema.Place.Params{rid: :red, type: :normal},
        %Schema.Place.Params{rid: :green, type: :normal},
        %Schema.Place.Params{rid: :end, type: :end}
      ],
      transitions: [
        %Schema.Transition.Params{rid: :init, executor: TrafficLight.Init},
        %Schema.Transition.Params{rid: :y2r, executor: TrafficLight.Y2R},
        %Schema.Transition.Params{rid: :r2g, executor: TrafficLight.R2G},
        %Schema.Transition.Params{rid: :g2y, executor: TrafficLight.G2Y},
        %Schema.Transition.Params{rid: :will_end, executor: TrafficLight.WillEnd}
      ],
      arcs: [
        %Schema.Arc.Params{place_rid: :start, transition_rid: :init, direction: :out},
        %Schema.Arc.Params{place_rid: :yellow, transition_rid: :init, direction: :in},
        %Schema.Arc.Params{place_rid: :yellow, transition_rid: :y2r, direction: :out},
        %Schema.Arc.Params{place_rid: :yellow, transition_rid: :g2y, direction: :in},
        %Schema.Arc.Params{place_rid: :red, transition_rid: :y2r, direction: :in},
        %Schema.Arc.Params{place_rid: :red, transition_rid: :will_end, direction: :out},
        %Schema.Arc.Params{place_rid: :red, transition_rid: :r2g, direction: :out},
        %Schema.Arc.Params{place_rid: :green, transition_rid: :r2g, direction: :in},
        %Schema.Arc.Params{place_rid: :green, transition_rid: :g2y, direction: :out},
        %Schema.Arc.Params{place_rid: :end, transition_rid: :will_end, direction: :in}
      ]
    }
  )

# Create a case
# ```elixir
# WorkflowMetal.Case.Supervisor.create_case TrafficLight, %Schema.Case.Params{workflow_id: traffic_light_workflow.id}
# ```
WorkflowMetal.Case.Supervisor.create_case(TrafficLight.Workflow, %Schema.Case.Params{
  workflow_id: traffic_light_workflow.id
})
