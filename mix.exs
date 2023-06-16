defmodule WorkflowMetal.MixProject do
  use Mix.Project

  def project do
    [
      app: :workflow_metal,
      version: "0.3.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      build_per_environment: is_nil(System.get_env("GITHUB_ACTIONS")),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      source_url: "https://github.com/Byzanteam/workflow_metal"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :gen_state_machine]
    ]
  end

  defp description() do
    "Workflow engine based on PetriNet"
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Byzanteam/workflow_metal"}
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:doctor, "~> 0.17.0", only: [:dev]},
      {:gen_state_machine, "~> 3.0"},
      {:typed_struct, "~> 0.3.0"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:jet_credo, [github: "Byzanteam/jet_credo", only: [:dev, :test], runtime: false]},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end

  defp elixirc_paths(:test),
    do: [
      "lib",
      "test/support",
      "test/helpers"
    ]

  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "code.check": ["format --check-formatted", "doctor --summary", "credo --strict", "dialyzer"]
    ]
  end
end
