defmodule WorkflowMetal.Storage.Adapter do
  @moduledoc """
  Defines the behaviour to be implemented by a storage adapter to be used by WorkflowMetal.
  """

  @type adapter_meta :: map()
  @type application :: WorkflowMetal.Application.t()
  @type config :: keyword

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type workflow_schema :: WorkflowMetal.Storage.Schema.Workflow.t()

  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type case_schema :: WorkflowMetal.Storage.Schema.Case.t()

  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()
  @type token_state :: WorkflowMetal.Storage.Schema.Token.state()
  @type token_states :: nonempty_list(token_state)

  @type error :: term()

  @type on_create_workflow ::
          :ok
          | {:error, :duplicate_workflow}
          | {:error, error}
  @type on_fetch_workflow ::
          {:ok, workflow_schema}
          | {:error, :workflow_not_found}
          | {:error, error}
  @type on_delete_workflow :: :ok

  @type on_create_case ::
          :ok
          | {:error, :workflow_not_found}
          | {:error, :duplicate_case}
          | {:error, error}
  @type on_fetch_case ::
          {:ok, case_schema}
          | {:error, :workflow_not_found}
          | {:error, :case_not_found}
          | {:error, error}

  @type on_fetch_token ::
          {:ok, list(token_schema)}
          | {:error, :workflow_not_found}
          | {:error, :case_not_found}
          | {:error, error}

  @doc """
  Return a child spec for the storage 
  """
  @callback child_spec(application, config) ::
              {:ok, :supervisor.child_spec() | {module, term} | module, adapter_meta}

  @doc """
  Create a workflow.
  """
  @callback create_workflow(
              adapter_meta,
              workflow_schema
            ) :: on_create_workflow

  @doc """
  Retrive a workflow.
  """
  @callback fetch_workflow(
              adapter_meta,
              workflow_id
            ) :: on_fetch_workflow

  @doc """
  Delete a specified workflow.
  """
  @callback delete_workflow(
              adapter_meta,
              workflow_id
            ) :: on_delete_workflow

  @doc """
  Create a case.
  """
  @callback create_case(
              adapter_meta,
              case_schema
            ) :: on_create_case

  @doc """
  Retrive a case.
  """
  @callback fetch_case(
              adapter_meta,
              workflow_id,
              case_id
            ) :: on_fetch_case

  @doc """
  Retrive tokens of a case.
  """
  @callback fetch_tokens(
              adapter_meta,
              workflow_id,
              case_id,
              token_states
            ) :: on_fetch_token
end