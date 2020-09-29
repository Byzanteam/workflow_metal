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

    use WorkflowMetal.Executor, application: Workflow

    alias WorkflowMetal.Storage.Schema

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, _options) do
      {:ok, _tokens} = preexecute(workitem)

      IO.puts("\n#{TrafficLight.now()} the light is on.")

      {:completed, :inited}
    end
  end

  defmodule Y2R do
    @moduledoc false

    use WorkflowMetal.Executor, application: Workflow

    alias WorkflowMetal.Storage.Schema

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      IO.puts("\n#{TrafficLight.now()} the light is about to turning red in 1s.")

      Task.start(__MODULE__, :run, [workitem, options])
      :started
    end

    def run(%Schema.Workitem{} = workitem, _options) do
      Process.sleep(1000)

      {:ok, _tokens} = preexecute(workitem)

      complete_workitem(workitem, :turn_red)

      TrafficLight.log_light(:red)
    end
  end

  defmodule R2G do
    @moduledoc false

    use WorkflowMetal.Executor, application: Workflow

    alias WorkflowMetal.Storage.Schema

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      IO.puts("\n#{TrafficLight.now()} the light is about to turning green in 5s.")

      Task.start(__MODULE__, :run, [workitem, options])
      :started
    end

    def run(%Schema.Workitem{} = workitem, _options) do
      Process.sleep(5000)

      case preexecute(workitem) do
        {:ok, _tokens} ->
          complete_workitem(workitem, :turn_green)

          TrafficLight.log_light(:green)

        _ ->
          abandon_workitem(workitem)
      end
    end
  end

  defmodule G2Y do
    @moduledoc false

    use WorkflowMetal.Executor, application: Workflow

    alias WorkflowMetal.Storage.Schema

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, options) do
      IO.puts("\n#{TrafficLight.now()} the light is about to turning yellow in 4s.")

      Task.start(__MODULE__, :run, [workitem, options])
      :started
    end

    def run(%Schema.Workitem{} = workitem, _options) do
      Process.sleep(4000)

      {:ok, _tokens} = preexecute(workitem)

      complete_workitem(workitem, :turn_yellow)

      TrafficLight.log_light(:yellow)
    end
  end

  defmodule WillEnd do
    @moduledoc false

    use WorkflowMetal.Executor, application: Workflow

    alias WorkflowMetal.Storage.Schema

    @impl WorkflowMetal.Executor
    def execute(%Schema.Workitem{} = workitem, _options) do
      # 50% chance
      if :rand.uniform(10) <= 5 do
        case preexecute(workitem) do
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

  def make_id, do: :erlang.unique_integer([:positive, :monotonic])
end

{:ok, _pid} = TrafficLight.Workflow.start_link()

{:ok, traffic_light_workflow} =
  WorkflowMetal.Storage.insert_workflow(
    TrafficLight.Workflow,
    %Schema.Workflow{
      id: :traffic_light,
      state: :active
    },
    %{
      places: [
        %Schema.Place{id: :start, type: :start, workflow_id: :traffic_light},
        %Schema.Place{id: :yellow, type: :normal, workflow_id: :traffic_light},
        %Schema.Place{id: :red, type: :normal, workflow_id: :traffic_light},
        %Schema.Place{id: :green, type: :normal, workflow_id: :traffic_light},
        %Schema.Place{id: :end, type: :end, workflow_id: :traffic_light}
      ],
      transitions: [
        %Schema.Transition{
          id: :init,
          join_type: :none,
          split_type: :none,
          executor: TrafficLight.Init,
          workflow_id: :traffic_light
        },
        %Schema.Transition{
          id: :y2r,
          join_type: :none,
          split_type: :none,
          executor: TrafficLight.Y2R,
          workflow_id: :traffic_light
        },
        %Schema.Transition{
          id: :r2g,
          join_type: :none,
          split_type: :none,
          executor: TrafficLight.R2G,
          workflow_id: :traffic_light
        },
        %Schema.Transition{
          id: :g2y,
          join_type: :none,
          split_type: :none,
          executor: TrafficLight.G2Y,
          workflow_id: :traffic_light
        },
        %Schema.Transition{
          id: :will_end,
          join_type: :none,
          split_type: :none,
          executor: TrafficLight.WillEnd,
          workflow_id: :traffic_light
        }
      ],
      arcs: [
        %Schema.Arc{
          id: TrafficLight.make_id(),
          place_id: :start,
          transition_id: :init,
          direction: :out,
          workflow_id: :traffic_light
        },
        %Schema.Arc{
          id: TrafficLight.make_id(),
          place_id: :yellow,
          transition_id: :init,
          direction: :in,
          workflow_id: :traffic_light
        },
        %Schema.Arc{
          id: TrafficLight.make_id(),
          place_id: :yellow,
          transition_id: :y2r,
          direction: :out,
          workflow_id: :traffic_light
        },
        %Schema.Arc{
          id: TrafficLight.make_id(),
          place_id: :yellow,
          transition_id: :g2y,
          direction: :in,
          workflow_id: :traffic_light
        },
        %Schema.Arc{
          id: TrafficLight.make_id(),
          place_id: :red,
          transition_id: :y2r,
          direction: :in,
          workflow_id: :traffic_light
        },
        %Schema.Arc{
          id: TrafficLight.make_id(),
          place_id: :red,
          transition_id: :will_end,
          direction: :out,
          workflow_id: :traffic_light
        },
        %Schema.Arc{
          id: TrafficLight.make_id(),
          place_id: :red,
          transition_id: :r2g,
          direction: :out,
          workflow_id: :traffic_light
        },
        %Schema.Arc{
          id: TrafficLight.make_id(),
          place_id: :green,
          transition_id: :r2g,
          direction: :in,
          workflow_id: :traffic_light
        },
        %Schema.Arc{
          id: TrafficLight.make_id(),
          place_id: :green,
          transition_id: :g2y,
          direction: :out,
          workflow_id: :traffic_light
        },
        %Schema.Arc{
          id: TrafficLight.make_id(),
          place_id: :end,
          transition_id: :will_end,
          direction: :in,
          workflow_id: :traffic_light
        }
      ]
    }
  )

{:ok, case_schema} =
  WorkflowMetal.Storage.insert_case(
    TrafficLight.Workflow,
    %Schema.Case{
      id: 1,
      state: :created,
      workflow_id: traffic_light_workflow.id
    }
  )

TrafficLight.Workflow.open_case(case_schema.id)
