defmodule WorkflowMetal.Storage.Adapter do
  @moduledoc """
  Defines the behaviour to be implemented by a storage adapter to be used by WorkflowMetal.
  """

  @type adapter_meta :: map()
  @type application :: WorkflowMetal.Application.t()
  @type config :: keyword

  @type workflow_id :: WorkflowMetal.Workflow.Supervisor.workflow_id()
  @type workflow_version :: WorkflowMetal.Workflow.Supervisor.workflow_version()
  @type workflow_data :: map()

  @type error :: term()

  @doc """
  Return a child spec for the storage 
  """
  @callback child_spec(application, config) ::
              {:ok, :supervisor.child_spec() | {module, term} | module, adapter_meta}

  @doc """
  Create or update a workflow.
  """
  @callback upsert_workflow(
              adapter_meta,
              workflow_id,
              workflow_version,
              workflow_data
            ) ::
              {:ok, :created}
              | {:ok, :updated}
              | {:error, error}

  @doc """
  Retrive a workflow.
  """
  @callback retrive_workflow(
              adapter_meta,
              workflow_id,
              workflow_version
            ) ::
              {:ok, workflow_data}
              | {:error, :workflow_not_found}
              | {:error, :workflow_version_not_found}
              | {:error, error}

  @doc """
  Delete a specified version workflow.
  """
  @callback delete_workflow(
              adapter_meta,
              workflow_id,
              workflow_version :: workflow_version | :all
            ) :: :ok
end
