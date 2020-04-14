defmodule WorkflowMetal.Storage do
  alias WorkflowMetal.Application

  @moduledoc """
  Use the storage configured for a WorkflowMetal application.
  """

  @type application :: WorkflowMetal.Application.t()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()

  @type workflow_params :: WorkflowMetal.Storage.Schema.Workflow.Params.t()

  @type arc_direction :: WorkflowMetal.Storage.Schema.Arc.direction()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()

  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type case_params :: WorkflowMetal.Storage.Schema.Case.Params.t()

  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()
  @type task_params :: WorkflowMetal.Storage.Schema.Task.Params.t()

  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type token_state :: WorkflowMetal.Storage.Schema.Token.state()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()
  @type token_payload :: WorkflowMetal.Storage.Schema.Token.payload()
  @type token_states :: nonempty_list(token_state)

  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()
  @type workitem_params :: WorkflowMetal.Storage.Schema.Workitem.Params.t()
  @type workitem_output :: WorkflowMetal.Storage.Schema.Workitem.output()

  @type config :: keyword()

  @doc """
  Get the configured storage adapter for the given application.
  """
  @spec adapter(application, config) :: {module, config}
  def adapter(application, config)

  def adapter(application, nil) do
    raise ArgumentError, "missing :storage config for application " <> inspect(application)
  end

  def adapter(application, config) do
    adapter = Keyword.fetch!(config, :storage)

    case Code.ensure_compiled(adapter) do
      {:module, _module} ->
        {adapter, []}

      _ ->
        raise ArgumentError,
              "storage adapter `" <>
                inspect(adapter) <>
                "` used by application `" <>
                inspect(application) <>
                "` was not compiled, ensure it is correct and it is included as a project dependency"
    end
  end

  # API
  ## Workflow

  @doc false
  @spec create_workflow(application, workflow_params) ::
          WorkflowMetal.Storage.Adapter.on_create_workflow()
  def create_workflow(application, workflow_params) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.create_workflow(
      adapter_meta,
      workflow_params
    )
  end

  @doc false
  @spec fetch_workflow(application, workflow_id) ::
          WorkflowMetal.Storage.Adapter.on_fetch_workflow()
  def fetch_workflow(application, workflow_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_workflow(
      adapter_meta,
      workflow_id
    )
  end

  @doc false
  @spec delete_workflow(application, workflow_id) ::
          WorkflowMetal.Storage.Adapter.on_delete_workflow()
  def delete_workflow(application, workflow_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.delete_workflow(
      adapter_meta,
      workflow_id
    )
  end

  @doc false
  @spec fetch_arcs(application, transition_id, arc_direction) ::
          WorkflowMetal.Storage.Adapter.on_fetch_arcs()
  def fetch_arcs(application, transition_id, arc_direction) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_arcs(
      adapter_meta,
      transition_id,
      arc_direction
    )
  end

  @doc false
  @spec fetch_places(application, transition_id, arc_direction) ::
          WorkflowMetal.Storage.Adapter.on_fetch_places()
  def fetch_places(application, transition_id, arc_direction) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_places(
      adapter_meta,
      transition_id,
      arc_direction
    )
  end

  @doc false
  @spec fetch_edge_places(application, workflow_id) ::
          WorkflowMetal.Storage.Adapter.on_fetch_edge_places()
  def fetch_edge_places(application, workflow_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_edge_places(
      adapter_meta,
      workflow_id
    )
  end

  @doc false
  @spec fetch_transition(application, transition_id) ::
          WorkflowMetal.Storage.Adapter.on_fetch_transition()
  def fetch_transition(application, transition_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_transition(
      adapter_meta,
      transition_id
    )
  end

  @doc false
  @spec fetch_transitions(application, place_id, arc_direction) ::
          WorkflowMetal.Storage.Adapter.on_fetch_transitions()
  def fetch_transitions(application, place_id, arc_direction) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_transitions(
      adapter_meta,
      place_id,
      arc_direction
    )
  end

  ## Case

  @doc false
  @spec create_case(application, case_params) ::
          WorkflowMetal.Storage.Adapter.on_create_case()
  def create_case(application, case_params) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.create_case(
      adapter_meta,
      case_params
    )
  end

  @doc false
  @spec fetch_case(application, case_id) ::
          WorkflowMetal.Storage.Adapter.on_fetch_case()
  def fetch_case(application, case_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_case(
      adapter_meta,
      case_id
    )
  end

  @doc false
  @spec update_case(
          application,
          case_id,
          WorkflowMetal.Storage.Adapter.update_case_params()
        ) ::
          WorkflowMetal.Storage.Adapter.on_update_case()
  def update_case(application, case_id, update_case_params) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.update_case(
      adapter_meta,
      case_id,
      update_case_params
    )
  end

  ## Task
  @doc false
  @spec create_task(application, task_params) ::
          WorkflowMetal.Storage.Adapter.on_create_task()
  def create_task(application, task_params) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.create_task(
      adapter_meta,
      task_params
    )
  end

  @doc false
  @spec fetch_task(application, task_id) ::
          WorkflowMetal.Storage.Adapter.on_fetch_task()
  def fetch_task(application, task_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_task(
      adapter_meta,
      task_id
    )
  end

  @doc false
  @spec fetch_available_task(application, case_id, transition_id) ::
          WorkflowMetal.Storage.Adapter.on_fetch_available_task()
  def fetch_available_task(application, case_id, transition_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_available_task(
      adapter_meta,
      case_id,
      transition_id
    )
  end

  @doc false
  @spec fetch_tasks(
          application,
          case_id,
          WorkflowMetal.Storage.Adapter.task_states()
        ) ::
          WorkflowMetal.Storage.Adapter.on_fetch_tasks()
  def fetch_tasks(application, case_id, task_states) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_tasks(
      adapter_meta,
      case_id,
      task_states
    )
  end

  @doc false
  @spec update_task(
          application,
          task_id,
          WorkflowMetal.Storage.Adapter.update_task_params()
        ) ::
          WorkflowMetal.Storage.Adapter.on_update_task()
  def update_task(application, task_id, update_task_params) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.update_task(
      adapter_meta,
      task_id,
      update_task_params
    )
  end

  ## Token

  @doc false
  @spec issue_token(application, token_params) ::
          WorkflowMetal.Storage.Adapter.on_issue_token()
  def issue_token(application, token_params) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.issue_token(
      adapter_meta,
      token_params
    )
  end

  @doc false
  @spec lock_token(application, token_id, task_id) ::
          WorkflowMetal.Storage.Adapter.on_lock_token()
  def lock_token(application, token_id, task_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.lock_token(
      adapter_meta,
      token_id,
      task_id
    )
  end

  @doc false
  @spec consume_tokens(application, nonempty_list(token_id), task_id) ::
          WorkflowMetal.Storage.Adapter.on_consume_tokens()
  def consume_tokens(application, token_ids, task_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.consume_tokens(
      adapter_meta,
      token_ids,
      task_id
    )
  end

  @doc false
  @spec fetch_locked_tokens(application, task_id) ::
          WorkflowMetal.Storage.Adapter.on_fetch_locked_tokens()
  def fetch_locked_tokens(application, task_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_locked_tokens(
      adapter_meta,
      task_id
    )
  end

  @doc false
  @spec fetch_tokens(application, case_id, token_states) ::
          WorkflowMetal.Storage.Adapter.on_fetch_tokens()
  def fetch_tokens(application, case_id, token_states) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_tokens(
      adapter_meta,
      case_id,
      token_states
    )
  end

  ## Workitem

  @doc false
  @spec create_workitem(application, workitem_params) ::
          WorkflowMetal.Storage.Adapter.on_create_workitem()
  def create_workitem(application, workitem_params) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.create_workitem(
      adapter_meta,
      workitem_params
    )
  end

  @doc false
  @spec fetch_workitems(application, task_id) ::
          WorkflowMetal.Storage.Adapter.on_fetch_workitems()
  def fetch_workitems(application, task_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_workitems(
      adapter_meta,
      task_id
    )
  end

  @doc false
  @spec update_workitem(
          application,
          workitem_id,
          WorkflowMetal.Storage.Adapter.update_workitem_params()
        ) ::
          WorkflowMetal.Storage.Adapter.on_update_workitem()
  def update_workitem(application, workitem_id, update_workitem_params) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.update_workitem(
      adapter_meta,
      workitem_id,
      update_workitem_params
    )
  end
end
