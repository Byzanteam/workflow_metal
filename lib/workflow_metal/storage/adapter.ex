defmodule WorkflowMetal.Storage.Adapter do
  @moduledoc """
  Defines the behaviour to be implemented by a storage adapter to be used by WorkflowMetal.
  """

  @type adapter_meta :: map()
  @type application :: WorkflowMetal.Application.t()
  @type config :: keyword

  @doc """
  Return a child spec for the storage
  """
  @callback child_spec(application, config) ::
              {:ok, :supervisor.child_spec() | {module, term} | module, adapter_meta}

  # Workflow

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type workflow_schema :: WorkflowMetal.Storage.Schema.Workflow.t()
  @type workflow_associations_params :: %{
          places: [place_schema()],
          transitions: [transition_schema()],
          arcs: [arc_schema()]
        }

  @type on_insert_workflow :: {:ok, workflow_schema}
  @type on_fetch_workflow :: {:ok, workflow_schema}
  @type on_delete_workflow :: :ok

  @doc """
  Insert a workflow.
  """
  @callback insert_workflow(
              adapter_meta,
              workflow_schema,
              workflow_associations_params
            ) :: on_insert_workflow

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

  # Places, Transitions, and Arcs

  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type place_schema :: WorkflowMetal.Storage.Schema.Place.t()

  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type transition_schema :: WorkflowMetal.Storage.Schema.Transition.t()

  @type arc_schema :: WorkflowMetal.Storage.Schema.Arc.t()
  @type arc_direction :: WorkflowMetal.Storage.Schema.Arc.direction()
  @type arc_beginning :: {:transition, transition_id} | {:place, place_id}

  @type on_fetch_arcs ::
          {:ok, [arc_schema]}
          | {:error, :workflow_not_found}
  @type on_fetch_edge_places ::
          {:ok, {place_schema, place_schema}}
  @type on_fetch_places ::
          {:ok, [place_schema]}
          | {:error, :transition_not_found}
  @type on_fetch_transition ::
          {:ok, transition_schema}
          | {:error, :transition_not_found}
  @type on_fetch_transitions ::
          {:ok, [transition_schema]}
          | {:error, :place_not_found}

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
  Retrive arcs of a workflow.
  """
  @callback fetch_arcs(
              adapter_meta,
              arc_beginning,
              arc_direction
            ) :: on_fetch_arcs

  # Case

  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type case_schema :: WorkflowMetal.Storage.Schema.Case.t()
  @type case_state :: WorkflowMetal.Storage.Schema.Case.state()
  @type update_case_params :: %{
          optional(:state) => case_state
        }

  @type on_insert_case ::
          {:ok, case_schema}
          | {:error, :workflow_not_found}
  @type on_fetch_case ::
          {:ok, case_schema}
          | {:error, :case_not_found}
  @type on_update_case ::
          {:ok, case_schema}
          | {:error, :case_not_found}

  @doc """
  Insert a case.
  """
  @callback insert_case(
              adapter_meta,
              case_schema
            ) :: on_insert_case

  @doc """
  Retrive a case.
  """
  @callback fetch_case(
              adapter_meta,
              case_id
            ) :: on_fetch_case

  @doc """
  Update the case.

  ### update_case_params:
  #### State
  - `:active`
  - `:terminated`
  - `:finished`
  """
  @callback update_case(
              adapter_meta,
              case_id | case_schema,
              update_case_params
            ) :: on_update_case

  # Task

  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()
  @type task_state :: WorkflowMetal.Storage.Schema.Task.state()
  @type task_schema :: WorkflowMetal.Storage.Schema.Task.t()
  @type update_task_params :: %{
          optional(:state) => task_state,
          optional(:token_payload) => token_payload()
        }
  @type fetch_tasks_options ::
          [
            states: nonempty_list(task_state) | nil,
            transition_id: transition_id
          ]
          | [transition_id: transition_id]

  @type on_insert_task ::
          {:ok, task_schema}
          | {:error, :workflow_not_found}
          | {:error, :transition_not_found}
          | {:error, :case_not_found}
  @type on_fetch_task ::
          {:ok, task_schema}
          | {:error, :task_not_found}
  @type on_fetch_tasks ::
          {:ok, [task_schema]}
          | {:error, :case_not_found}
  @type on_update_task ::
          {:ok, task_schema}
          | {:error, :task_not_found}
          | {:error, :task_not_available}

  @doc """
  Create a task.
  """
  @callback insert_task(
              adapter_meta,
              task_schema
            ) :: on_insert_task

  @doc """
  Retrive a task.
  """
  @callback fetch_task(
              adapter_meta,
              task_id
            ) :: on_fetch_task

  @doc """
  Retrive tasks of a case.
  """
  @callback fetch_tasks(
              adapter_meta,
              case_id,
              fetch_tasks_options
            ) :: on_fetch_tasks

  @doc """
  Update the task.

  update_task_params: `State` and `TokenPayload`
  """
  @callback update_task(
              adapter_meta,
              task_id,
              update_task_params
            ) :: on_update_task

  # Token

  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()
  @type token_state :: WorkflowMetal.Storage.Schema.Token.state()
  @type token_payload :: WorkflowMetal.Storage.Schema.Token.payload()

  @type on_issue_token ::
          {:ok, token_schema}
          | {:error, :workflow_not_found}
          | {:error, :case_not_found}
          | {:error, :place_not_found}
  @type on_lock_tokens ::
          {:ok, token_schema}
          | {:error, :tokens_not_available}
  @type on_unlock_tokens :: {:ok, [token_schema]}
  @type on_consume_tokens ::
          {:ok, [token_schema]}
          | {:error, :tokens_not_available}
  @type on_fetch_tokens ::
          {:ok, [token_schema]}
          | {:error, :task_not_found}
  @type on_fetch_unconsumed_tokens :: {:ok, [token_schema]}

  @doc """
  Issue a token.

  If produced_by_task_id is `:genesis`, the token is a genesis token.
  """
  @callback issue_token(
              adapter_meta,
              token_schema
            ) :: on_issue_token

  @doc """
  Lock tokens atomically.
  """
  @callback lock_tokens(
              adapter_meta,
              token_ids :: nonempty_list(token_id),
              locked_by_task_id :: task_id
            ) :: on_lock_tokens

  @doc """
  Unlock tokens that locked by the task.
  """
  @callback unlock_tokens(
              adapter_meta,
              [token_id]
            ) :: on_unlock_tokens

  @doc """
  Consume tokens that locked by the task.
  """
  @callback consume_tokens(
              adapter_meta,
              [token_id],
              task_id | :termination
            ) :: on_consume_tokens

  @doc """
  Retrive tokens of the task.
  """
  @callback fetch_unconsumed_tokens(
              adapter_meta,
              case_id
            ) :: on_fetch_unconsumed_tokens

  @doc """
  Retrive tokens of the task.
  """
  @callback fetch_tokens(
              adapter_meta,
              [token_id]
            ) :: on_fetch_tokens

  # Workitem

  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()
  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()
  @type workitem_state :: WorkflowMetal.Storage.Schema.Workitem.state()
  @type workitem_output :: WorkflowMetal.Storage.Schema.Workitem.output()
  @type update_workitem_params :: %{
          optional(:state) => workitem_state,
          optional(:output) => workitem_output
        }

  @type on_insert_workitem ::
          {:ok, workitem_schema}
          | {:error, :workflow_not_found}
          | {:error, :case_not_found}
          | {:error, :task_not_found}
  @type on_fetch_workitem ::
          {:ok, workitem_schema}
          | {:error, :workitem_not_found}
  @type on_fetch_workitems ::
          {:ok, [workitem_schema]}
          | {:error, :task_not_found}
  @type on_update_workitem ::
          {:ok, workitem_schema}
          | {:error, :workitem_not_found}
          | {:error, :workitem_not_available}

  @doc """
  Insert a workitem of a task.
  """
  @callback insert_workitem(
              adapter_meta,
              workitem_schema
            ) :: on_insert_workitem

  @doc """
  Fetch a workitem of a task.
  """
  @callback fetch_workitem(
              adapter_meta,
              workitem_id
            ) :: on_fetch_workitem

  @doc """
  Retrive workitems generated by the task.
  """
  @callback fetch_workitems(
              adapter_meta,
              task_id
            ) :: on_fetch_workitems

  @doc """
  Update the workitem.

  update_workitem_params: `State` and `Output`.
  """
  @callback update_workitem(
              adapter_meta,
              workitem_id,
              update_workitem_params
            ) :: on_update_workitem
end
