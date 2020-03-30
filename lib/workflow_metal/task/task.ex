defmodule WorkflowMetal.Task.Task do
  @moduledoc """
  A `GenServer` to hold tokens, execute conditions and generate `workitem`.
  """

  use GenServer

  defstruct [
    :application,
    :workflow_id,
    :case_id,
    :transition_id,
    :transition,
    :token_table,
    :workitem_table
  ]

  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()

  @doc false
  @spec start_link(workflow_identifier, case_id, transition_id) :: GenServer.on_start()
  def start_link({application, workflow_id} = workflow_identifier, case_id, transition_id) do
    via_name =
      WorkflowMetal.Registration.via_tuple(
        application,
        name({workflow_id, case_id, transition_id})
      )

    GenServer.start_link(__MODULE__, {workflow_identifier, case_id, transition_id}, name: via_name)
  end

  @doc false
  @spec name({workflow_id, case_id, transition_id}) :: term()
  def name({workflow_id, case_id, transition_id}) do
    {__MODULE__, {workflow_id, case_id, transition_id}}
  end

  @doc """
  Offer a token.
  """
  @spec offer_token(GenServer.server(), place_id, token_id) :: :ok
  def offer_token(transition_server, place_id, token_id) do
    GenServer.cast(transition_server, {:offer_token, place_id, token_id})
  end

  @doc """
  Withdraw a token.
  """
  @spec withdraw_token(GenServer.server(), place_id, token_id) :: :ok
  def withdraw_token(transition_server, place_id, token_id) do
    GenServer.cast(transition_server, {:withdraw_token, place_id, token_id})
  end

  # callbacks

  @impl true
  def init({{application, workflow_id}, case_id, transition_id}) do
    token_table = :ets.new(:token_table, [:set, :private])
    workitem_table = :ets.new(:workitem_table, [:set, :private])

    {
      :ok,
      %__MODULE__{
        application: application,
        workflow_id: workflow_id,
        case_id: case_id,
        transition_id: transition_id,
        token_table: token_table,
        workitem_table: workitem_table
      },
      {:continue, :fetch_transition}
    }
  end

  @impl true
  def handle_continue(:fetch_transition, %__MODULE__{} = state) do
    %{transition_id: transition_id} = state

    workflow_server = workflow_server(state)

    {:ok, transition} =
      WorkflowMetal.Workflow.Workflow.fetch_transition(workflow_server, transition_id)

    {:noreply, %{state | transition: transition}}
  end

  @impl true
  def handle_continue(:fire_transition, %__MODULE__{} = state) do
    if enabled?(state) do
      # TODO: lock token
      # TODO: generate workitem
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:offer_token, place_id, token_id}, %__MODULE__{} = state) do
    %{token_table: token_table} = state
    :ets.insert(token_table, {token_id, place_id, :free})

    {:noreply, state, {:continue, :fire_transition}}
  end

  @impl true
  def handle_cast({:withdraw_token, place_id, token_id}, %__MODULE__{} = state) do
    # TODO: remove token from token_table
  end

  defp enabled?(%__MODULE__{} = state) do
    %{
      transition_id: transition_id,
      transition: transition,
      token_table: token_table
    } = state

    workflow_server = workflow_server(state)

    {:ok, places} =
      WorkflowMetal.Workflow.Workflow.fetch_places(workflow_server, transition_id, :in)

    # TODO: fetch in arcs with places
    # TODO: consider conditions on the arc
    # WorkflowMetal.Workflow.Workflow.fetch_arcs(workflow_server, transition_id, :in)
    Enum.all?(places, fn place ->
      # TODO: use select_count
      # :ets.select_count > 0
      case transition.join_type do
        :none ->
          [] !== :ets.select(token_table, [{{:"$1", place.id, :free}, [], [:"$1"]}])

        _ ->
          false
      end
    end)
  end

  defp workflow_server(%__MODULE__{} = state) do
    %{application: application, workflow_id: workflow_id} = state

    WorkflowMetal.Workflow.Workflow.via_name(application, workflow_id)
  end
end
