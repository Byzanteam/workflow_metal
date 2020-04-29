defmodule WorkflowMetal.Controller.Split do
  @moduledoc false

  alias WorkflowMetal.Storage.Schema

  @type task_data :: WorkflowMetal.Task.Task.t()
  @type token_payload :: WorkflowMetal.Storage.Schema.Token.payload()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()

  @type on_issue_tokens :: {:ok, [token_params]}

  @doc false
  @callback issue_tokens(
              task_data,
              token_payload
            ) :: on_issue_tokens

  @doc false
  @spec issue_tokens(task_data, token_payload) :: on_issue_tokens
  def issue_tokens(task_data, token_payload) do
    %{
      transition_schema: %Schema.Transition{
        split_type: split_type
      }
    } = task_data

    controller(split_type).issue_tokens(task_data, token_payload)
  end

  defp controller(:none), do: WorkflowMetal.Controller.Split.None
  defp controller(:and), do: WorkflowMetal.Controller.Split.And
  defp controller(controller_module) when is_atom(controller_module), do: controller_module
end
