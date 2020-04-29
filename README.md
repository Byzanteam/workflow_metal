# WorkflowMetal

![CI](https://github.com/Byzanteam/workflow_metal/workflows/CI/badge.svg)

**Workflow engine based on PetriNet**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `workflow_metal` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:workflow_metal, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/workflow_metal](https://hexdocs.pm/workflow_metal).

## Test in shell

```shell
iex --dot-iex examples/traffic_light.exs -S mix
```
