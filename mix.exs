defmodule ExTradier.MixProject do
  use Mix.Project

  @version "0.1.2"
  @source_url "https://github.com/drdray1/ex_tradier"

  def project do
    [
      app: :ex_tradier,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "Elixir client for the Tradier brokerage API",
      package: package(),

      # Test coverage
      test_coverage: [
        ignore_modules: [
          ExTradier.Streaming.Client,
          ExTradier.Streaming.Client.State,
          ExTradier.Application
        ]
      ],

      # Docs
      name: "ExTradier",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExTradier.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:decimal, "~> 2.0 or ~> 3.0"},
      {:websockex, "~> 0.4"},
      {:plug, "~> 1.14", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.7", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "ExTradier",
      extras: ["README.md"],
      groups_for_modules: [
        "REST API": [
          ExTradier.User,
          ExTradier.MarketData,
          ExTradier.Trading,
          ExTradier.Watchlist
        ],
        Authentication: [
          ExTradier.Auth
        ],
        Streaming: [
          ExTradier.Streaming,
          ExTradier.Streaming.Client,
          ExTradier.Streaming.MarketConnection,
          ExTradier.Streaming.AccountConnection
        ],
        Client: [
          ExTradier.Client
        ]
      ]
    ]
  end
end
