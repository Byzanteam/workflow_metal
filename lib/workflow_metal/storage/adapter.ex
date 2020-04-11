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
  @type arc_direction :: WorkflowMetal.Storage.Schema.Arc.direction()

  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type place_schema :: WorkflowMetal.Storage.Schema.Place.t()

  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type transition_schema :: WorkflowMetal.Storage.Schema.Transition.t()

  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type case_params :: WorkflowMetal.Storage.Schema.Case.Params.t()
  @type case_schema :: WorkflowMetal.Storage.Schema.Case.t()

  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()
  @type task_params :: WorkflowMetal.Storage.Schema.Task.Params.t()
  @type task_schema :: WorkflowMetal.Storage.Schema.Task.t()
  @type update_task_params :: :executing | {:completed, token_payload}

  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()
  @type token_state :: WorkflowMetal.Storage.Schema.Token.state()
  @type token_payload :: WorkflowMetal.Storage.Schema.Token.payload()
  @type token_states :: nonempty_list(token_state)

  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()
  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()
  @type workitem_params :: WorkflowMetal.Storage.Schema.Workitem.Params.t()
  @type workitem_output :: WorkflowMetal.Storage.Schema.Workitem.output()
  @type update_workitem_params :: :started | {:completed, workitem_output} | :abandoned

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
  @type on_fetch_edge_places ::
          {:ok, {place_schema, place_schema}}
          | {:error, :workflow_not_found}
  @type on_fetch_places ::
          {:ok, [place_schema]}
          | {:error, :transition_not_found}
  @type on_fetch_transition ::
          {:ok, transition_schema}
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
  @type on_activate_case ::
          {:ok, case_schema}
          | {:error, :case_not_found}
  @type on_finish_case ::
          {:ok, case_schema}
          | {:error, :case_not_found}

  @type on_create_task ::
          {:ok, task_schema}
          | {:error, :workflow_not_found}
          | {:error, :transition_not_found}
          | {:error, :case_not_found}
  @type on_fetch_task ::
          {:ok, task_schema}
          | {:error, :task_not_found}
  @type on_execute_task ::
          {:ok, task_schema}
          | {:error, :task_not_found}
          | {:error, :task_not_available}
  @type on_complete_task ::
          {:ok, task_schema}
          | {:error, :task_not_found}
          | {:error, :task_not_available}
  @type on_update_task ::
          {:ok, task_schema}
          | {:error, :task_not_found}
          | {:error, :task_not_available}

  @type on_issue_token ::
          {:ok, token_schema}
          | {:error, :workflow_not_found}
          | {:error, :case_not_found}
          | {:error, :place_not_found}
          | {:error, :produced_by_task_not_found}
  @type on_lock_token ::
          {:ok, token_schema}
          | {:error, :token_not_found}
          | {:error, :token_not_available}
  @type on_consume_tokens ::
          {:ok, [token_schema]}
          | {:error, :token_not_available}
  @type on_fetch_tokens ::
          {:ok, [token_schema]}
  @type on_fetch_locked_tokens ::
          {:ok, [token_schema]}
          | {:error, :task_not_found}

  @type on_create_workitem ::
          {:ok, workitem_schema}
          | {:error, :workflow_not_found}
          | {:error, :case_not_found}
          | {:error, :task_not_found}
  @type on_fetch_workitems ::
          {:ok, [workitem_schema]}
          | {:error, :task_not_found}
  @type on_start_workitem ::
          {:ok, workitem_schema}
          | {:error, :workitem_not_found}
          | {:error, :workitem_not_available}
  @type on_complete_workitem ::
          {:ok, workitem_schema}
          | {:error, :workitem_not_found}
          | {:error, :workitem_not_available}
  @type on_update_workitem ::
          {:ok, workitem_schema}
          | {:error, :workitem_not_found}
          | {:error, :workitem_not_available}

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
  @callback fetch_arcs(
              adapter_meta,
              transition_id,
              arc_direction
            ) :: on_fetch_arcs

  @doc """
  Retrive start and end of a workflow.
  """
  @callback fetch_edge_places(
              adapter_meta,
              workflow_id
            ) :: on_fetch_edge_places

  @doc """
  Retrive in/out places of a transition.
  """
  @callback fetch_places(
              adapter_meta,
              transition_id,
              arc_direction
            ) :: on_fetch_places

  @doc """
  Retrive a transition of the workflow.
  """
  @callback fetch_transition(
              adapter_meta,
              transition_id
            ) :: on_fetch_transition

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

  @doc """
  Activate a case.
  """
  @callback activate_case(
              adapter_meta,
              case_id
            ) :: on_activate_case

  @doc """
  Finish a case.
  """
  @callback finish_case(
              adapter_meta,
              case_id
            ) :: on_finish_case

  # Task
  @doc """
  Create a task.
  """
  @callback create_task(
              adapter_meta,
              task_params
            ) :: on_create_task

  @doc """
  Retrive a task.
  """
  @callback fetch_task(
              adapter_meta,
              task_id
            ) :: on_fetch_task
  @callback fetch_task(
              adapter_meta,
              case_id,
              transition_id
            ) :: on_fetch_task

  @doc """
  Start to execute a task.

  Return `{:ok, task_schema}` if it is already `executing`.
  """
  @callback execute_task(
              adapter_meta,
              workitem_id
            ) :: on_execute_task

  @doc """
  Complete a task.
  """
  @callback complete_task(
              adapter_meta,
              task_id,
              token_payload
            ) :: on_complete_task

  @doc """
  Update the task.

  ### update_task_params:
  - `:executing`
  - `{:completed, task_output}`

  note: if the state of the task is the state in the update_task,
  it returns `{:ok, task_schema}` too.
  """
  @callback update_task(
              adapter_meta,
              task_id,
              update_task_params
            ) :: on_update_task

  # Token
  @doc """
  Issue a token.

  If produced_by_task_id not provided, the token is a genesis token.
  """
  @callback issue_token(
              adapter_meta,
              token_params
            ) :: on_issue_token
  @doc """
  Lock a token.
  """
  @callback lock_token(
              adapter_meta,
              token_id,
              task_id
            ) :: on_lock_token
  @doc """
  Consume tokens.
  """
  @callback consume_tokens(
              adapter_meta,
              nonempty_list(token_id),
              task_id
            ) :: on_consume_tokens
  @doc """
  Retrive tokens locked by the task.
  """
  @callback fetch_locked_tokens(
              adapter_meta,
              task_id
            ) :: on_fetch_locked_tokens

  # Workitem
  @doc """
  Fetch tokens by states
  """
  @callback fetch_tokens(
              adapter_meta,
              case_id,
              token_states
            ) :: on_fetch_tokens

  @doc """
  Create a workitem of a task.
  """
  @callback create_workitem(
              adapter_meta,
              workitem_params
            ) :: on_create_workitem

  @doc """
  Retrive workitems generated by the task.
  """
  @callback fetch_workitems(
              adapter_meta,
              task_id
            ) :: on_fetch_workitems
  @doc """
  Start to execute a `created` workitem of a task.

  Return `{:ok, workitem_schema}` if it is already `started`.
  """
  @callback start_workitem(
              adapter_meta,
              workitem_id
            ) :: on_start_workitem

  @doc """
  Complete a `started` workitem of a task, and put an output into the workitem.

  Return `{:ok, workitem_schema}` if it is already `completed`.
  """
  @callback complete_workitem(
              adapter_meta,
              workitem_id,
              workitem_output
            ) :: on_complete_workitem

  @doc """
  Update the workitem.

  ### update_workitem_params:
  - `:started`
  - `{:completed, workitem_output}`
  - `:abandoned`

  note: if the state of the workitem is the state in the update_workitem,
  it returns `{:ok, workitem_schema}` too.
  """
  @callback update_workitem(
              adapter_meta,
              workitem_id,
              update_workitem_params
            ) :: on_update_workitem
end
