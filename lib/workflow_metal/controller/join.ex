defmodule WorkflowMetal.Controller.Join do
  @moduledoc """
  Join controller.
  """

  alias WorkflowMetal.Storage.Schema

  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type task_data :: WorkflowMetal.Task.Task.t()

  @type on_task_enablement :: :ok | {:error, :task_not_enabled}

  @doc false
  @callback task_enablement(task_data) :: on_task_enablement

  @doc false
  @spec task_enablement(task_data) :: on_task_enablement
  def task_enablement(task_data) do
    %{
      transition_schema: %Schema.Transition{
        join_type: join_type
      }
    } = task_data

    controller(join_type).task_enablement(task_data)
  end

  defp controller(:none), do: WorkflowMetal.Controller.Join.None
  defp controller(:and), do: WorkflowMetal.Controller.Join.And
  defp controller(controller_module) when is_atom(controller_module), do: controller_module
end
