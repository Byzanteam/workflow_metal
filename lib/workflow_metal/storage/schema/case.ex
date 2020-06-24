defmodule WorkflowMetal.Storage.Schema.Case do
  @moduledoc """
  ## State
  - `:created`: the case is just created, we'll put a token in the `:start` place
  - `:active`: the case is running
  - `:canceled`: the case can be canceled by a user who created it or the system
  - `:finished`: when there is only one token left in the `:end` place
  """

  @enforce_keys [:id, :workflow_id]
  defstruct [
    :id,
    :workflow_id,
    :data,
    state: :created
  ]

  @type id :: term()
  @type state :: :created | :active | :canceled | :finished

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type data :: term()

  @type t() :: %__MODULE__{
          id: id,
          workflow_id: workflow_id,
          state: state,
          data: data
        }

  alias __MODULE__

  defmodule Params do
    @moduledoc false

    @enforce_keys [:workflow_id]
    defstruct [
      :workflow_id,
      :data
    ]

    @type t() :: %__MODULE__{
            workflow_id: Case.workflow_id(),
            data: Case.data()
          }
  end
end
