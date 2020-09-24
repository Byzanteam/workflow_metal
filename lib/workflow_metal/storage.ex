defmodule WorkflowMetal.Storage do
  alias WorkflowMetal.Application
  alias WorkflowMetal.Storage.Adapter

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
  @type case_schema :: WorkflowMetal.Storage.Schema.Case.t()

  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()
  @type task_schema :: WorkflowMetal.Storage.Schema.Task.t()

  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type token_state :: WorkflowMetal.Storage.Schema.Token.state()
  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()
  @type token_payload :: WorkflowMetal.Storage.Schema.Token.payload()
  @type token_states :: nonempty_list(token_state)

  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()
  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()
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
    {adapter, storage_config} =
      case Keyword.fetch!(config, :storage) do
        {adapter, keywords} -> {adapter, keywords}
        adapter -> {adapter, []}
      end

    case Code.ensure_compiled(adapter) do
      {:module, _module} ->
        {adapter, storage_config}

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
  ## util
  @doc false
  @spec generate_id(application, Adapter.schema_type(), map()) :: Adapter.on_generate_id()
  def generate_id(application, schema_type, options) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.generate_id(
      adapter_meta,
      schema_type,
      options
    )
  end

  ## Workflow

  @doc false
  @spec create_workflow(application, workflow_params) ::
          Adapter.on_create_workflow()
  def create_workflow(application, workflow_params) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.create_workflow(
      adapter_meta,
      workflow_params
    )
  end

  @doc false
  @spec fetch_workflow(application, workflow_id) ::
          Adapter.on_fetch_workflow()
  def fetch_workflow(application, workflow_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_workflow(
      adapter_meta,
      workflow_id
    )
  end

  @doc false
  @spec delete_workflow(application, workflow_id) ::
          Adapter.on_delete_workflow()
  def delete_workflow(application, workflow_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.delete_workflow(
      adapter_meta,
      workflow_id
    )
  end

  ## Places, Transitions, and Arcs

  @doc false
  @spec fetch_edge_places(application, workflow_id) ::
          Adapter.on_fetch_edge_places()
  def fetch_edge_places(application, workflow_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_edge_places(
      adapter_meta,
      workflow_id
    )
  end

  @doc false
  @spec fetch_places(application, transition_id, arc_direction) ::
          Adapter.on_fetch_places()
  def fetch_places(application, transition_id, arc_direction) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_places(
      adapter_meta,
      transition_id,
      arc_direction
    )
  end

  @doc false
  @spec fetch_transition(application, transition_id) ::
          Adapter.on_fetch_transition()
  def fetch_transition(application, transition_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_transition(
      adapter_meta,
      transition_id
    )
  end

  @doc false
  @spec fetch_transitions(application, place_id, arc_direction) ::
          Adapter.on_fetch_transitions()
  def fetch_transitions(application, place_id, arc_direction) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_transitions(
      adapter_meta,
      place_id,
      arc_direction
    )
  end

  @doc false
  @spec fetch_arcs(application, Adapter.arc_beginning(), arc_direction) ::
          Adapter.on_fetch_arcs()
  def fetch_arcs(application, arc_beginning, arc_direction) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_arcs(
      adapter_meta,
      arc_beginning,
      arc_direction
    )
  end

  ## Case

  @doc false
  @spec insert_case(application, case_schema) ::
          Adapter.on_insert_case()
  def insert_case(application, case_schema) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.insert_case(adapter_meta, case_schema)
  end

  @doc false
  @spec fetch_case(application, case_id) ::
          Adapter.on_fetch_case()
  def fetch_case(application, case_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_case(
      adapter_meta,
      case_id
    )
  end

  @doc false
  @spec update_case(application, case_id, Adapter.update_case_params()) ::
          Adapter.on_update_case()
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
  @spec insert_task(application, task_schema) ::
          Adapter.on_insert_task()
  def insert_task(application, task_schema) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.insert_task(adapter_meta, task_schema)
  end

  @doc false
  @spec fetch_task(application, task_id) ::
          Adapter.on_fetch_task()
  def fetch_task(application, task_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_task(
      adapter_meta,
      task_id
    )
  end

  @doc false
  @spec fetch_tasks(application, case_id, Adapter.fetch_tasks_options()) ::
          Adapter.on_fetch_tasks()
  def fetch_tasks(application, case_id, options) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_tasks(
      adapter_meta,
      case_id,
      options
    )
  end

  @doc false
  @spec update_task(application, task_id, Adapter.update_task_params()) ::
          Adapter.on_update_task()
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
  @spec issue_token(application, token_schema) ::
          Adapter.on_issue_token()
  def issue_token(application, token_schema) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.issue_token(
      adapter_meta,
      token_schema
    )
  end

  @doc false
  @spec lock_tokens(application, nonempty_list(token_id), task_id) ::
          Adapter.on_lock_tokens()
  def lock_tokens(application, token_ids, locked_by_task_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.lock_tokens(
      adapter_meta,
      token_ids,
      locked_by_task_id
    )
  end

  @doc false
  @spec unlock_tokens(application, task_id) :: Adapter.on_unlock_tokens()
  def unlock_tokens(application, locked_by_task_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.unlock_tokens(
      adapter_meta,
      locked_by_task_id
    )
  end

  @doc false
  @spec consume_tokens(application, task_id | {case_id, :termination}) ::
          Adapter.on_consume_tokens()
  def consume_tokens(application, locked_by_task_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.consume_tokens(
      adapter_meta,
      locked_by_task_id
    )
  end

  @doc false
  @spec fetch_tokens(application, case_id, Adapter.fetch_tokens_options()) ::
          Adapter.on_fetch_tokens()
  def fetch_tokens(application, case_id, options) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_tokens(
      adapter_meta,
      case_id,
      options
    )
  end

  ## Workitem

  @doc false
  @spec insert_workitem(application, workitem_schema) ::
          Adapter.on_insert_workitem()
  def insert_workitem(application, workitem_schema) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.insert_workitem(
      adapter_meta,
      workitem_schema
    )
  end

  @doc false
  @spec fetch_workitem(application, workitem_id) ::
          Adapter.on_fetch_workitem()
  def fetch_workitem(application, workitem_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_workitem(
      adapter_meta,
      workitem_id
    )
  end

  @doc false
  @spec fetch_workitems(application, task_id) ::
          Adapter.on_fetch_workitems()
  def fetch_workitems(application, task_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_workitems(
      adapter_meta,
      task_id
    )
  end

  @doc false
  @spec update_workitem(application, workitem_id, Adapter.update_workitem_params()) ::
          Adapter.on_update_workitem()
  def update_workitem(application, workitem_id, update_workitem_params) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.update_workitem(
      adapter_meta,
      workitem_id,
      update_workitem_params
    )
  end
end
