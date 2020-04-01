defmodule WorkflowMetal.Storage.Schema.Token do
  @moduledoc false

  @enforce_keys [:id, :state, :workflow_id, :case_id, :place_id]
  defstruct [
    :id,
    :state,
    :workflow_id,
    :case_id,
    :place_id,
    :locked_workitem_id
  ]

  @type id :: term()
  @type state :: :free | :locked | :consumed
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type place_id :: WorkflowMetal.Storage.Schema.Place.id()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()

  @type t() :: %__MODULE__{
          id: id,
          state: state,
          workflow_id: workflow_id,
          case_id: case_id,
          place_id: place_id,
          locked_workitem_id: workitem_id
        }

  defmodule Params do
    @moduledoc false

    @enforce_keys [:state, :workflow_id, :case_id, :place_id]
    defstruct [:state, :workflow_id, :case_id, :place_id]

    alias WorkflowMetal.Storage.Schema.Token

    @type t() :: %{
            state: Token.state(),
            workflow_id: Token.workflow_id(),
            case_id: Token.case_id(),
            place_id: Token.place_id()
          }
  end
end
