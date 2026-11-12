defmodule Mix.Tasks.Cadmpeg.Mcp do
  @shortdoc "Serves CAD files to an MCP client over stdio"

  @moduledoc """
  Runs the Model Context Protocol server: one JSON-RPC message per line on stdin,
  one answer per line on stdout, until stdin closes.

  This is what an MCP client launches, so it says nothing on stdout that is not a
  protocol message — a stray `IO.puts` here is a message the client cannot parse.
  Anything worth saying goes to stderr.

      # .mcp.json / mcp.json, in a project that depends on ex_cadmpeg
      {"mcpServers": {"cadmpeg": {"command": "mix", "args": ["cadmpeg.mcp"]}}}

  The tools are `Cadmpeg.Mcp.Tools`; what the server is for is in `Cadmpeg.Mcp`.
  """

  use Mix.Task

  @impl true
  def run(_arguments) do
    Mix.Task.run("app.start")

    # The engine is the whole point: a server that cannot read a file is better
    # named as one that is not built than discovered to be by its first call.
    if Cadmpeg.loaded?() do
      Cadmpeg.Mcp.serve()
    else
      IO.puts(:stderr, "the Rust engine is not built here: run `mix compile` (it needs cargo)")
      exit({:shutdown, 1})
    end
  end
end
