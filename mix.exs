defmodule Strukt.MixProject do
  use Mix.Project

  def project do
    [
      app: :strukt,
      version: "0.2.1",
      elixir: "~> 1.11",
      description: description(),
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: [
        docs: :docs,
        "hex.publish": :docs
      ],
      name: "Strukt",
      source_url: "https://github.com/bitwalker/strukt",
      homepage_url: "http://github.com/bitwalker/strukt",
      docs: [
        main: "readme",
        api_reference: false,
        extra_section: "Extras",
        extras: [
          "guides/usage.md",
          "guides/schemas.md",
          "guides/json.md",
          {:"README.md", [title: "About"]},
          {:"LICENSE.md", [title: "License"]}
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.0"},
      {:jason, "> 0.0.0", optional: true},
      {:uniq, "~> 0.1", only: [:test]},
      {:ex_doc, "> 0.0.0", only: [:docs], runtime: false}
    ]
  end

  defp description do
    "Extends defstruct with schemas, changeset validation, and more"
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Paul Schoenfelder"],
      licenses: ["Apache 2.0"],
      links: %{
        GitHub: "https://github.com/bitwalker/strukt"
      }
    ]
  end
end
