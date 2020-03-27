defmodule WorkflowMetal.Workflow.Workflow do
  @moduledoc """
  Workflow is a `GenServer` process used to provide access to a workflow.
  """

  use GenServer

  defstruct [
    :application,
    :workflow_id,
    :place_table,
    :transition_table,
    :arc_table
  ]

  @type application :: WorkflowMetal.Application.t()
  @type workflow :: WorkflowMetal.Storage.Schema.Workflow.t()

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type workflow_identifier :: {application, workflow_id}

  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type place_schema :: WorkflowMetal.Storage.Schema.Place.t()

  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type transition_schema :: WorkflowMetal.Storage.Schema.Transition.t()

  @type arc_direction :: WorkflowMetal.Storage.Schema.Arc.direction()

  @arc_directions [:in, :out]

  @doc false
  @spec start_link(workflow_identifier) :: GenServer.on_start()
  def start_link({application, workflow_id} = workflow_identifier) do
    via_name =
      WorkflowMetal.Registration.via_tuple(
        application,
        name(workflow_id)
      )

    GenServer.start_link(__MODULE__, workflow_identifier, name: via_name)
  end

  @doc false
  @spec name(workflow_identifier) :: term()
  def name(workflow_id) do
    {__MODULE__, workflow_id}
  end

  @doc false
  @spec via_name(application, workflow_identifier) :: term()
  def via_name(application, workflow_id) do
    WorkflowMetal.Registration.via_tuple(application, name(workflow_id))
  end

  @doc """
  Retrive transistions of a place.
  """
  @spec fetch_transitions(GenServer.server(), place_id, arc_direction) ::
          {:ok, [transition_schema]} | {:error, term()}
  def fetch_transitions(workflow_server, place_id, direction) do
    GenServer.call(workflow_server, {:fetch_transitions, place_id, direction})
  end

  @doc """
  Retrive places of a transition.
  """
  @spec fetch_places(GenServer.server(), place_id, arc_direction) ::
          {:ok, [place_schema]} | {:error, term()}
  def fetch_places(workflow_server, transition_id, direction) do
    GenServer.call(workflow_server, {:fetch_places, transition_id, direction})
  end

  # Server (callbacks)

  @impl true
  def init({application, workflow_id}) do
    place_table = :ets.new(:place_table, [:set, :private])
    transition_table = :ets.new(:transition_table, [:set, :private])
    arc_table = :ets.new(:arc_table, [:bag, :private])

    {
      :ok,
      %__MODULE__{
        application: application,
        workflow_id: workflow_id,
        place_table: place_table,
        transition_table: transition_table,
        arc_table: arc_table
      },
      {:continue, :rebuild_from_storage}
    }
  end

  @impl true
  def handle_continue(:rebuild_from_storage, %__MODULE__{} = state) do
    %{
      application: application,
      workflow_id: workflow_id
    } = state

    case WorkflowMetal.Storage.fetch_workflow(application, workflow_id) do
      {:ok, workflow_schema} ->
        %{
          places: places,
          transitions: transitions,
          arcs: arcs
        } = workflow_schema

        with(
          {:ok, state} <- insert_places(places, state),
          {:ok, state} <- insert_transitions(transitions, state),
          {:ok, state} <- insert_arcs(arcs, state)
        ) do
          {:noreply, state}
        else
          error ->
            error
        end

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_call({:fetch_transitions, place_id, direction}, _from, %__MODULE__{} = state)
      when direction in @arc_directions do
    %{arc_table: arc_table} = state

    transitions =
      :ets.select(
        arc_table,
        [{{{place_id, :_, direction}, :_, :"$1"}, [], [:"$1"]}]
      )

    {:reply, {:ok, transitions}, state}
  end

  @impl true
  def handle_call({:fetch_places, transition_id, direction}, _from, %__MODULE__{} = state)
      when direction in @arc_directions do
    reversed_direction =
      case direction do
        :in -> :out
        :out -> :in
      end

    %{arc_table: arc_table} = state

    places =
      :ets.select(
        arc_table,
        [{{{:_, transition_id, reversed_direction}, :"$1", :_}, [], [:"$1"]}]
      )

    {:reply, {:ok, places}, state}
  end

  defp insert_places(places, %__MODULE__{} = state) do
    %{place_table: table} = state

    Enum.each(places, fn place ->
      :ets.insert(table, {place.id, place.type, place})
    end)

    {:ok, state}
  end

  defp insert_transitions(transitions, %__MODULE__{} = state) do
    %{transition_table: table} = state

    Enum.each(transitions, fn transition ->
      :ets.insert(table, {transition.id, transition})
    end)

    {:ok, state}
  end

  defp insert_arcs(arcs, %__MODULE__{} = state) do
    %{
      arc_table: arc_table,
      place_table: place_table,
      transition_table: transition_table
    } = state

    get_place = fn place_id ->
      place_table
      |> :ets.select([{{place_id, :_, :"$1"}, [], [:"$1"]}])
      |> hd()
    end

    get_transition = fn transition_id ->
      transition_table
      |> :ets.select([{{transition_id, :"$1"}, [], [:"$1"]}])
      |> hd()
    end

    Enum.each(arcs, fn arc ->
      %{
        place_id: place_id,
        transition_id: transition_id,
        direction: direction
      } = arc

      :ets.insert(
        arc_table,
        {
          {place_id, transition_id, direction},
          get_place.(place_id),
          get_transition.(transition_id)
        }
      )
    end)

    {:ok, state}
  end
end
