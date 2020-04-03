defmodule WorkflowMetal.Support.InMemoryStorageCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  setup context do
    case Map.get(context, :application) do
      nil ->
        :ok

      storage ->
        on_exit(fn ->
          :ok = WorkflowMetal.Storage.Adapters.InMemory.reset!(storage)
        end)
    end
  end
end
