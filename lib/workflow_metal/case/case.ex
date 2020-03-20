defmodule WorkflowMetal.Case.Case do
  @moduledoc """
  `GenServer` process to present a workflow case.
  """

  use GenServer

  @type case_params :: WorkflowMetal.Case.Supervisor.case_params()

  @doc false
  @spec name(case_params) :: term
  def name(case_params) do
    case_id = Keyword.fetch!(case_params, :case_id)
    {__MODULE__, case_id}
  end

  @impl true
  def init(init_args) do
    {:ok, init_args}
  end
end
