defmodule WorkflowMetal.Support.InMemoryStorageCase do
  @moduledoc false

  alias WorkflowMetal.Storage.Adapters.InMemory, InMemoryStorage

  use ExUnit.CaseTemplate

  setup context do
    case Map.get(context, :application) do
      nil ->
        :ok

      storage ->
        on_exit(fn ->
          :ok = InMemoryStorage.reset!(storage)
        end)
    end
  end
end
