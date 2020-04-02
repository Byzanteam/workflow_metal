defmodule WorkflowMetal.Storage.Adapter do
  @moduledoc """
  Defines the behaviour to be implemented by a storage adapter to be used by WorkflowMetal.
  """

  @type adapter_meta :: map()
  @type application :: WorkflowMetal.Application.t()
  @type config :: keyword

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type workflow_params :: WorkflowMetal.Storage.Schema.Workflow.Params.t()
  @type workflow_schema :: WorkflowMetal.Storage.Schema.Workflow.t()

  @type arc_schema :: WorkflowMetal.Storage.Schema.Arc.t()
  @type place_schema :: WorkflowMetal.Storage.Schema.Place.t()
  @type transition_schema :: WorkflowMetal.Storage.Schema.Transition.t()

  @type arc_direction :: WorkflowMetal.Storage.Schema.Arc.direction()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()

  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type case_params :: WorkflowMetal.Storage.Schema.Case.Params.t()
  @type case_schema :: WorkflowMetal.Storage.Schema.Case.t()

  @type task_schema :: WorkflowMetal.Storage.Schema.Task.t()
  @type task_params :: WorkflowMetal.Storage.Schema.Task.Params.t()

  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()
  @type token_state :: WorkflowMetal.Storage.Schema.Token.state()

  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()
  @type workitem_params :: WorkflowMetal.Storage.Schema.Workitem.Params.t()

  @type error :: term()

  @type on_create_workflow ::
          :ok
          | {:error, :duplicate_workflow}
  @type on_fetch_workflow ::
          {:ok, workflow_schema}
          | {:error, :workflow_not_found}
  @type on_delete_workflow :: :ok

  @type on_fetch_arcs ::
          {:ok, [arc_schema]}
          | {:error, :workflow_not_found}
  @type on_fetch_places ::
          {:ok, [place_schema]}
          | {:error, :transition_not_found}
  @type on_fetch_transitions ::
          {:ok, [transition_schema]}
          | {:error, :place_not_found}

  @type on_create_case ::
          {:ok, case_schema}
          | {:error, :workflow_not_found}
  @type on_fetch_case ::
          {:ok, case_schema}
          | {:error, :case_not_found}

  @type on_create_task ::
          {:ok, task_schema}
          | {:error, :workflow_not_found}
          | {:error, :transition_not_found}
          | {:error, :case_not_found}

  @type on_issue_token ::
          {:ok, token_schema}
          | {:error, :workflow_not_found}
          | {:error, :case_not_found}
          | {:error, :place_not_found}
          | {:error, :produced_by_task_not_found}
  @type on_fetch_locked_tokens ::
          {:ok, [token_schema]}
          | {:error, :task_not_found}

  @type on_create_workitem ::
          {:ok, workitem_schema}
          | {:error, :workflow_not_found}
          | {:error, :case_not_found}
          | {:error, :task_not_found}
          | {:error, error}
  @type on_update_workitem ::
          {:ok, workitem_schema}
          | {:error, :workitem_not_found}
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
              workflow_params
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
  Retrive arcs of a workflow.
  """
  @callback fetch_arcs(
              adapter_meta,
              workflow_id
            ) :: on_fetch_arcs

  @doc """
  Retrive in/out places of a transition.
  """
  @callback fetch_places(
              adapter_meta,
              transition_id,
              arc_direction
            ) :: on_fetch_places

  @doc """
  Retrive in/out transitions of a place.
  """
  @callback fetch_transitions(
              adapter_meta,
              place_id,
              arc_direction
            ) :: on_fetch_transitions

  @doc """
  Create a case.
  """
  @callback create_case(
              adapter_meta,
              case_params
            ) :: on_create_case

  @doc """
  Retrive a case.
  """
  @callback fetch_case(
              adapter_meta,
              case_id
            ) :: on_fetch_case

  # Task
  @doc """
  Create a task.
  """
  @callback create_task(
              adapter_meta,
              task_params
            ) :: on_create_task

  # Token
  @doc """
  Issue a token.
  """
  @callback issue_token(
              adapter_meta,
              token_params
            ) :: on_issue_token
  @doc """
  Retrive tokens locked by the task.
  """
  @callback fetch_locked_tokens(
              adapter_meta,
              task_id
            ) :: on_fetch_locked_tokens

  # Workitem
  @doc """
  Create a workitem of a task.
  """
  @callback create_workitem(
              adapter_meta,
              workitem_params
            ) :: on_create_workitem

  @doc """
  Update a workitem of a task.
  """
  @callback update_workitem(
              adapter_meta,
              workitem_schema
            ) :: on_update_workitem
end
