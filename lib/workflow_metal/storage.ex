defmodule WorkflowMetal.Storage do
  alias WorkflowMetal.Application

  @moduledoc """
  Use the storage configured for a WorkflowMetal application.
  """

  @type application :: Application.t()
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
  def upsert_workflow(application, workflow_id, workflow_version, workflow_data) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.upsert_workflow(
      adapter_meta,
      workflow_id,
      workflow_version,
      workflow_data
    )
  end

  @doc false
  def retrive_workflow(application, workflow_id, workflow_version) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.retrive_workflow(
      adapter_meta,
      workflow_id,
      workflow_version
    )
  end

  @doc false
  def delete_workflow(application, workflow_id, workflow_version) do
    {adapter, adapter_meta} = Application.storage_adapter(application)

    adapter.delete_workflow(
      adapter_meta,
      workflow_id,
      workflow_version
    )
  end
end
