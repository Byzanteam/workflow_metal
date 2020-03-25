defmodule WorkflowMetal.Storage.Adapter do
  @moduledoc """
  Defines the behaviour to be implemented by a storage adapter to be used by WorkflowMetal.
  """

  @type adapter_meta :: map()
  @type application :: WorkflowMetal.Application.t()
  @type config :: keyword

  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type workflow_data :: term()

  @type error :: term()

  @type on_create_workflow ::
          :ok
          | {:error, :duplicate_workflow}
          | {:error, error}
  @type on_retrive_workflow ::
          {:ok, workflow_data}
          | {:error, :workflow_not_found}
          | {:error, error}
  @type on_delete_workflow :: :ok

  @doc """
  Return a child spec for the storage 
  """
  @callback child_spec(application, config) ::
              {:ok, :supervisor.child_spec() | {module, term} | module, adapter_meta}

  @doc """
  Create or update a workflow.
  """
  @callback create_workflow(
              adapter_meta,
              workflow_id,
              workflow_data
            ) :: on_create_workflow

  @doc """
  Retrive a workflow.
  """
  @callback retrive_workflow(
              adapter_meta,
              workflow_id
            ) :: on_retrive_workflow

  @doc """
  Delete a specified workflow.
  """
  @callback delete_workflow(
              adapter_meta,
              workflow_id
            ) :: on_delete_workflow
end
