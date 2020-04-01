defmodule WorkflowMetal.Storage do
  alias WorkflowMetal.Application

  @moduledoc """
  Use the storage configured for a WorkflowMetal application.
  """

  @type application :: WorkflowMetal.Application.t()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type workflow_schema :: WorkflowMetal.Storage.Schema.Workflow.t()

  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.t()

  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type case_schema :: WorkflowMetal.Storage.Schema.Case.t()

  @type task_schema :: WorkflowMetal.Storage.Schema.Task.t()
  @type task_params :: WorkflowMetal.Storage.Schema.Task.Params.t()

  @type token_state :: WorkflowMetal.Storage.Schema.Token.state()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()
  @type token_states :: nonempty_list(token_state)

  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()
  @type workitem_params :: WorkflowMetal.Storage.Schema.Workitem.Params.t()

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

  @doc false
  @spec create_workflow(application, workflow_schema) ::
          WorkflowMetal.Storage.Adapter.on_create_workflow()
  def create_workflow(application, workflow_schema) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.create_workflow(
      adapter_meta,
      workflow_schema
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
  @spec create_case(application, case_schema) ::
          WorkflowMetal.Storage.Adapter.on_create_case()
  def create_case(application, case_schema) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.create_case(
      adapter_meta,
      case_schema
    )
  end

  @doc false
  @spec fetch_case(application, workflow_id, case_id) ::
          WorkflowMetal.Storage.Adapter.on_fetch_case()
  def fetch_case(application, workflow_id, case_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_case(
      adapter_meta,
      workflow_id,
      case_id
    )
  end

  @doc false
  @spec create_task(application, task_schema) ::
          WorkflowMetal.Storage.Adapter.on_create_task()
  def create_task(application, task_schema) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.create_task(
      adapter_meta,
      task_schema
    )
  end

  @doc false
  @spec fetch_task(application, workflow_id, case_id, transition_id) ::
          WorkflowMetal.Storage.Adapter.on_fetch_task()
  def fetch_task(application, workflow_id, case_id, transition_id) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_task(
      adapter_meta,
      workflow_id,
      case_id,
      transition_id
    )
  end

  @doc false
  @spec create_token(application, token_params) ::
          WorkflowMetal.Storage.Adapter.on_create_token()
  def create_token(application, token_params) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.create_token(
      adapter_meta,
      token_params
    )
  end

  @doc false
  @spec fetch_tokens(application, workflow_id, case_id, token_states) ::
          WorkflowMetal.Storage.Adapter.on_fetch_tokens()
  def fetch_tokens(application, workflow_id, case_id, token_states) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.fetch_tokens(
      adapter_meta,
      workflow_id,
      case_id,
      token_states
    )
  end

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
  @spec update_workitem(application, workitem_schema) ::
          WorkflowMetal.Storage.Adapter.on_update_workitem()
  def update_workitem(application, workitem_schema) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.update_workitem(
      adapter_meta,
      workitem_schema
    )
  end
end
