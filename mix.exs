defmodule PlugCache.Mixfile do
  use Mix.Project

  @version "0.0.1"
  @github_url "https://github.com/ekosz/plug_cache"
  @description """
  HTTP caching layer for plug. Heavily inspried from rack-cache.
  """

  def project do
    [app: :plug_cache,
     version: @version,
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps,
     description: @description,
     name: 'Plug.Cache',
     source_url: @github_url,
     package: package]
  end

  def application do
    [applications: [:logger, :cowboy, :plug]]
  end

  defp deps do
    [{:cowboy, "~> 1.0"},
     {:plug, "~> 0.9"},
     {:timex, "~> 0.13.4"},
     {:earmark, "~> 0.1", only: :docs},
     {:ex_doc, "~> 0.7", only: :docs}]
  end

  def package do
    [contributors: ["Eric Koslow"],
     licenses: ["MIT"],
     links: %{"GitHub" => @github_url}]
  end
end
