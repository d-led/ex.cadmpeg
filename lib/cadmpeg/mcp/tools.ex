defmodule Cadmpeg.Mcp.Tools do
  @moduledoc """
  The tools the MCP server offers, and the one place a name becomes a function.

  A tool answers `{:ok, %{text: text, structured: map}, state}` or
  `{:error, message, state}`. The text is what a model reads; the structured part
  is the same answer for a program that would rather not parse prose. The
  protocol layer turns the second form into `isError`, which is how the
  specification says "this call failed, the message says how" rather than "the
  server is broken".

  Two tools read and one writes: `cadmpeg_convert` puts a file where the caller
  named it and nothing else.

  ## Where the files come from

  A call names a path, and the server keeps the document it opened, so asking
  three questions about one file reads it once — and a tool never takes a
  *handle* from a caller, because a handle is not something a model should have
  to hold.
  """

  alias Cadmpeg.{Document, Mcp}

  @read_only %{
    "readOnlyHint" => true,
    "destructiveHint" => false,
    "idempotentHint" => true,
    "openWorldHint" => false
  }

  @writes %{
    "readOnlyHint" => false,
    "destructiveHint" => true,
    "idempotentHint" => true,
    "openWorldHint" => false
  }

  @path %{
    "type" => "string",
    "description" => "The CAD file to read."
  }

  @catalogue [
    %{
      "name" => "cadmpeg_formats",
      "title" => "What this build reads and writes",
      "description" =>
        "The input formats compiled into this build, each with the file " <>
          "extensions it claims, and the output formats it can write. A format " <>
          "that is not listed cannot be read here, whatever the file is called.",
      "inputSchema" => %{"type" => "object", "properties" => %{}},
      "annotations" => @read_only
    },
    %{
      "name" => "cadmpeg_inspect",
      "title" => "What is in a CAD file, and how faithfully it was read",
      "description" =>
        "Opens a CAD file — native or STEP — and answers its decode report: the " <>
          "dialect it was read as, what was transferred, and every loss with its " <>
          "reason and severity. A file that opens with losses is a document of " <>
          "reduced fidelity, and this is where that is said.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"path" => @path},
        "required" => ["path"]
      },
      "annotations" => @read_only
    },
    %{
      "name" => "cadmpeg_convert",
      "title" => "Write the file out in another format",
      "description" =>
        "Reads a CAD file and writes the same document to `out` as `step` " <>
          "(ISO 10303-21) or `cadir` (cadmpeg's own JSON). Answers the export " <>
          "report: the entities written, and what the target could not carry. " <>
          "Writes the file you name and nothing else.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => @path,
          "format" => %{
            "type" => "string",
            "description" => "An output format this build carries, e.g. `step`."
          },
          "out" => %{"type" => "string", "description" => "Where to write it."},
          "target" => %{
            "type" => "string",
            "description" =>
              "A dialect inside the format, e.g. `ap242` for STEP. Omit to keep " <>
                "the dialect the document was read in."
          }
        },
        "required" => ["path", "format", "out"]
      },
      "annotations" => @writes
    }
  ]

  @doc "The tools, as the protocol wants them listed."
  @spec catalogue() :: [map()]
  def catalogue, do: @catalogue

  @doc "One tool call: its answer and the state after it."
  @spec call(String.t(), map(), Mcp.state()) :: {atom(), term(), Mcp.state()}
  def call("cadmpeg_formats", _arguments, state), do: formats_answer(state)

  def call("cadmpeg_inspect", arguments, state) do
    with {:ok, path} <- required(arguments, "path"),
         {:ok, document, state} <- open(path, state) do
      {:ok, inspect_answer(document), state}
    else
      {:error, message} -> {:error, message, state}
    end
  end

  def call("cadmpeg_convert", arguments, state) do
    with {:ok, path} <- required(arguments, "path"),
         {:ok, format} <- required(arguments, "format"),
         {:ok, out} <- required(arguments, "out"),
         {:ok, document, state} <- open(path, state),
         {:ok, report} <- write(document, format, out, arguments["target"]) do
      {:ok, convert_answer(out, format, report), state}
    else
      {:error, message} -> {:error, message, state}
    end
  end

  def call(name, _arguments, state), do: {:error, "no such tool: #{name}", state}

  defp formats_answer(state) do
    %{inputs: inputs, outputs: outputs} = Cadmpeg.formats()

    reads =
      inputs
      |> Enum.map_join("; ", fn input ->
        "#{input["format"]} (#{Enum.join(input["extensions"], ", ")})"
      end)

    text = """
    Reads: #{reads}
    Writes: #{Enum.join(outputs, ", ")}
    """

    {:ok, %{text: text, structured: %{"inputs" => inputs, "outputs" => outputs}}, state}
  end

  defp inspect_answer(document) do
    report = document.report
    losses = Map.get(report, "losses") || []

    text = """
    #{Path.basename(document.path)} — read as #{dialect(report)}, #{transfer(report)}
    #{describe_losses(losses)}
    """

    %{text: text, structured: %{"path" => document.path, "report" => report}}
  end

  defp convert_answer(out, format, report) do
    text = """
    Wrote #{out} as #{format} — #{census(report)}
    #{describe_losses(Map.get(report, "losses") || [])}
    """

    %{text: text, structured: %{"out" => out, "format" => format, "report" => report}}
  end

  defp dialect(report) do
    report
    |> get_in(["identity", "dialects", "primary", "dialect"])
    |> case do
      nil -> "an unrecorded dialect"
      dialect -> dialect
    end
  end

  defp transfer(report) do
    case report["transfer"] do
      %{"transfer" => "full", "geometry_transferred" => true} -> "geometry transferred in full"
      %{"transfer" => "full"} -> "transferred in full, geometry not carried"
      %{"transfer" => other} -> "transferred #{other}"
      _ -> "transfer not reported"
    end
  end

  defp census(report) do
    case get_in(report, ["census", "counts"]) do
      counts when is_map(counts) and map_size(counts) > 0 ->
        counts
        |> Enum.sort_by(fn {_record, count} -> -count end)
        |> Enum.take(6)
        |> Enum.map_join(", ", fn {record, count} -> "#{record} #{count}" end)

      _ ->
        "no entity census in the report"
    end
  end

  defp describe_losses([]), do: "No losses reported: the document is what the file held."

  defp describe_losses(losses) do
    by_severity =
      losses
      |> Enum.group_by(&Map.get(&1, "severity", "unspecified"))
      |> Enum.sort_by(fn {_severity, list} -> -length(list) end)
      |> Enum.map_join(", ", fn {severity, list} -> "#{length(list)} #{severity}" end)

    first = losses |> Enum.take(3) |> Enum.map_join("\n  ", &loss_line/1)

    "#{length(losses)} loss(es): #{by_severity}\n  #{first}"
  end

  defp loss_line(loss) do
    "- [#{loss["severity"]}] #{loss["message"]}"
  end

  defp required(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "#{key} is required"}
    end
  end

  defp open(path, state) do
    case Map.fetch(state.documents, path) do
      {:ok, document} ->
        {:ok, document, state}

      :error ->
        case Cadmpeg.open(path) do
          {:ok, document} -> {:ok, document, put_in(state.documents[path], document)}
          {:error, error} -> {:error, Mcp.describe_error(error)}
        end
    end
  end

  defp write(document, format, out, target) do
    options = if is_binary(target) and target != "", do: [target: target], else: []

    case Document.write(document, format, out, options) do
      {:ok, report} -> {:ok, report}
      {:error, error} -> {:error, Mcp.describe_error(error)}
    end
  end
end
