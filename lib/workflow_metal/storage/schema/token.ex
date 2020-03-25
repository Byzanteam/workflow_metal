defmodule WorkflowMetal.Storage.Schema.Token do
  @moduledoc false

  @enforce_keys [:id, :workflow_id, :case_id, :state, :produced_at]
  defstruct [
    :id,
    :workflow_id,
    :case_id,
    :place_id,
    :state,
    :locked_workitem_id,
    :produced_at,
    :locked_at,
    :canceled_at,
    :consumed_at
  ]

  @type t() :: %__MODULE__{
          id: any(),
          workflow_id: any(),
          case_id: any(),
          place_id: any(),
          state: :free | :locked | :canceled | :finished,
          locked_workitem_id: any(),
          produced_at: NaiveDateTime.t(),
          locked_at: NaiveDateTime.t(),
          canceled_at: NaiveDateTime.t(),
          consumed_at: NaiveDateTime.t()
        }
end
