defmodule WorkflowMetal.Controller.Split do
  @moduledoc false

  @type application :: WorkflowMetal.Application.t()
  @type arc_schema :: WorkflowMetal.Storage.Schema.Arc.t()
  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()

  @doc false
  @callback call(
              application,
              [arc_schema],
              token_schema
            ) :: Splitter.result()
end
