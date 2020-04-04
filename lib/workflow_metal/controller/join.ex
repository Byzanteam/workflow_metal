defmodule WorkflowMetal.Controller.Join do
  @moduledoc """
  Join controller.
  """

  alias WorkflowMetal.Storage.Schema

  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type task_state :: WorkflowMetal.Task.Task.t()

  @type on_task_enablement :: {:ok, nonempty_list(token_id)} | {:error, :task_not_enabled}

  @doc false
  @callback task_enablement(task_state) :: on_task_enablement

  @spec task_enablement(task_state) :: on_task_enablement
  def task_enablement(task_state) do
    %{
      transition_schema: %Schema.Transition{
        join_type: join_type
      }
    } = task_state

    controller(join_type).task_enablement(task_state)
  end

  defp controller(:none), do: WorkflowMetal.Controller.Join.None
  defp controller(:and), do: WorkflowMetal.Controller.Join.And
  defp controller(controller_module), do: controller_module
end
