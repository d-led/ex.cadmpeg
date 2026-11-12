defmodule Cadmpeg.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/d-led/ex.cadmpeg"

  def project do
    [
      app: :ex_cadmpeg,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
      docs: docs(),
      name: "ExCadmpeg",
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # The NIF crate under `native/cadmpeg_nif` is built when this package is:
      # that wants a Rust toolchain at build time, and nothing at run time beyond
      # the `.so` the release carries.
      {:rustler, "~> 0.38", runtime: false},

      # A decode report, an export report and the document's own JSON form are
      # documents: they arrive decoded rather than as structs for every shape.
      {:jason, "~> 1.2"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp description do
    "An Elixir wrapper of github.com/cadmpeg/cadmpeg to bring native CAD files onto " <>
      "the BEAM: SolidWorks, CATIA, Inventor, Creo, NX, Fusion, FreeCAD, Rhino, " <>
      "IGES and STEP read into one format-neutral CAD document, and that document " <>
      "written back out. Wrapped via rustler; no vendor SDK, no OpenCascade. This " <>
      "build compiles in the STEP codec."
  end

  defp package do
    [
      files: ~w(lib native/cadmpeg_nif/src native/cadmpeg_nif/Cargo.toml
                native/cadmpeg_nif/Cargo.lock native/cadmpeg_nif/.cargo docs mix.exs
                README.md CHANGELOG.md LICENSE NOTICE .formatter.exs),
      licenses: ["MPL-2.0"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Dmitry Ledentsov"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "docs/ir.md"],
      groups_for_modules: [
        "The document": [Cadmpeg, Cadmpeg.Document],
        Refusals: [Cadmpeg.Error],
        "Model Context Protocol": [Cadmpeg.Mcp, Cadmpeg.Mcp.Tools],
        "The engine": [Cadmpeg.Native]
      ]
    ]
  end
end
