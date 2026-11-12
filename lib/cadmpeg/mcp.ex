defmodule Cadmpeg.Mcp do
  @moduledoc """
  A Model Context Protocol server over stdio: a CAD file, for an assistant.

  One JSON-RPC message per line in, one out — the stdio transport, which is what
  a client launches as a process. No sessions, no server-sent events, no batches:
  every request is self-contained, which is what lets a client treat it as a
  pipe.

  ## What the tools are for

  cadmpeg answers "what is in this file, and can I have it as something else?" and
  this server exposes that:

    * **what can this build do?** — `cadmpeg_formats`: the formats it reads and
      the formats it writes;
    * **what is in this file, and how faithfully was it read?** —
      `cadmpeg_inspect`: the document and its decode report, which is where the
      losses are;
    * **give me another format** — `cadmpeg_convert`: write the document out as
      STEP or as its own JSON.

  ## Documents are opened once

  Calls name a path; the server keeps the opened document, so a second question
  about the same file does not read it again. The cache is this process's —
  restarting the server costs a re-read, and nothing on disk depends on it.

  A tool that cannot answer answers: a refusal is text saying what was wrong and
  what to try, never a dropped connection.
  """

  alias Cadmpeg.{Document, Error}
  alias Cadmpeg.Mcp.Tools

  @protocol_versions ~w(2025-06-18 2025-03-26 2024-11-05)

  @typedoc "What the server remembers between messages: the documents it has read."
  @type state :: %{documents: %{optional(String.t()) => Document.t()}}

  @doc "The protocol revisions this server speaks, newest first."
  @spec protocol_versions() :: [String.t()]
  def protocol_versions, do: @protocol_versions

  @doc """
  Reads JSON-RPC messages from stdin and writes answers to stdout until stdin
  closes.

  Notifications are answered with nothing, which is what the transport says.
  """
  @spec serve() :: :ok
  def serve do
    _ =
      IO.stream(:stdio, :line)
      |> Enum.reduce(fresh(), fn line, state ->
        {reply, state} = handle(String.trim_trailing(line), state)
        if reply, do: IO.puts(reply)
        state
      end)

    :ok
  end

  @doc "The state a new server starts with."
  @spec fresh() :: state()
  def fresh, do: %{documents: %{}}

  @doc """
  One message: the reply (or `nil` for a notification) and the state after it.

  `nil` for a blank line, and for a line that is not JSON — a transport that
  crashes on garbage is a transport nobody can debug.
  """
  @spec handle(String.t() | nil, state()) :: {String.t() | nil, state()}
  def handle(line, state) when line in ["", " ", nil], do: {nil, state}

  def handle(line, state) do
    case Jason.decode(line) do
      {:ok, message} when is_map(message) -> dispatch(message, state)
      {:ok, _not_an_object} -> {error_reply(nil, -32_600, "not a JSON-RPC object"), state}
      {:error, _reason} -> {error_reply(nil, -32_700, "the line is not JSON"), state}
    end
  end

  defp dispatch(%{"method" => method, "id" => id} = message, state) when is_binary(method) do
    case result(method, Map.get(message, "params", %{}), state) do
      {:ok, result, state} -> {reply(id, result), state}
      {:error, message} -> {error_reply(id, -32_601, message), state}
    end
  end

  defp dispatch(%{"method" => method} = message, state) when is_binary(method) do
    # A notification: do the work, answer nothing.
    _ = result(method, Map.get(message, "params", %{}), state)
    {nil, state}
  end

  defp dispatch(_message, state), do: {error_reply(nil, -32_600, "no method"), state}

  defp result("initialize", params, state) do
    {:ok,
     %{
       "protocolVersion" => negotiate(Map.get(params, "protocolVersion")),
       "capabilities" => %{"tools" => %{"listChanged" => false}},
       "serverInfo" => %{
         "name" => "ex-cadmpeg",
         "title" => "CAD files: read, report, convert",
         "version" => version()
       },
       "instructions" => instructions()
     }, state}
  end

  defp result("tools/list", _params, state), do: {:ok, %{"tools" => Tools.catalogue()}, state}

  defp result("tools/call", params, state) do
    name = Map.get(params, "name")
    arguments = Map.get(params, "arguments") || %{}

    case Tools.call(name, arguments, state) do
      {:ok, %{text: text, structured: structured}, state} ->
        {:ok,
         %{
           "content" => [%{"type" => "text", "text" => text}],
           "structuredContent" => structured,
           "isError" => false
         }, state}

      {:error, message, state} ->
        {:ok, %{"content" => [%{"type" => "text", "text" => message}], "isError" => true}, state}
    end
  end

  defp result("ping", _params, state), do: {:ok, %{}, state}

  defp result(method, _params, _state), do: {:error, "unknown method: #{method}"}

  defp negotiate(requested) do
    if requested in @protocol_versions, do: requested, else: hd(@protocol_versions)
  end

  defp instructions do
    """
    This server reads CAD files and can write them out in another format.

    THE FORMATS: cadmpeg_formats says what this build reads and what it writes.
    The codecs are compiled in, so that answer is a fact about the binary rather
    than a promise; a format that is not listed cannot be read here.

    A FILE: cadmpeg_inspect opens a path and answers the decode report — what was
    transferred and every loss with its reason. "It opened" and "it opened
    faithfully" are different answers, and the report is the second one.

    ANOTHER FORMAT: cadmpeg_convert reads a path and writes the same document as
    `step` (ISO 10303-21) or `cadir` (cadmpeg's own JSON), answering the export
    report: what was written, and what could not be carried.

    Paths are the interface. A native format that keeps parts of itself in files
    beside it is read against its own directory, which is why a file is named
    rather than bytes.
    """
  end

  defp version do
    case Application.spec(:ex_cadmpeg, :vsn) do
      nil -> "dev"
      version -> to_string(version)
    end
  end

  defp reply(id, result) do
    Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result})
  end

  defp error_reply(id, code, message) do
    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    })
  end

  @doc false
  @spec describe_error(Error.t()) :: String.t()
  def describe_error(%Error{code: code, message: message}), do: "#{code}: #{message}"
end
