defmodule Cadmpeg do
  @moduledoc """
  Native CAD files on the BEAM.

  [cadmpeg](https://github.com/cadmpeg/cadmpeg) reads the formats a shop
  actually has — SolidWorks `.sldprt`, CATIA `.CATPart`, Inventor `.ipt`/`.iam`,
  Creo, NX, Fusion `.f3d`, FreeCAD `.FCStd`, Rhino `.3dm`, IGES, STEP, Creo View,
  OpenUSD — into one format-neutral CAD IR, and writes that IR back out. This is
  a binding of it, so the same job is a function call rather than a translator
  process.

  ```elixir
  {:ok, document} = Cadmpeg.open("bracket.sldprt")
  {:ok, _report} = Cadmpeg.Document.write(document, "step", "bracket.step")
  ```

  ## A document is a value, and the geometry is a resource

  `open/1` reads a file once and answers a `Cadmpeg.Document` holding the parsed
  document. Every other call takes that handle, so the file is parsed once
  however many questions follow, and — because a B-rep never changes — one
  handle serves every process on the node. It cannot be sent to another node:
  the document is local.

  ## What the formats are, and what they are not

  `formats/0` answers what *this build* reads and writes. cadmpeg's codecs are
  compiled in by feature, so a build without the SolidWorks codec cannot read a
  `.sldprt` and says so instead of guessing — the list is a fact about the
  binary in the VM, not a promise.

  Support is a ladder, one level per format: a file that reads is not a promise
  that every feature was transferred. That is what the decode report is for, and
  it is why `open/1` answers the report beside the handle: "it opened" and "it
  opened faithfully" are different answers.

  ## Limits, said out loud

  - The document is read-only here. cadmpeg's IR can be edited, and this binding
    does not expose editing yet: `Cadmpeg.Document.to_json/1` is the way to a
    document a caller can change, and `from_json/1` the way back.
  - A decode is a best effort within cadmpeg's own ladder. A refusal arrives as
    `Cadmpeg.Error` with the code `"refused"` and the loss that caused it; it is
    not retried at a laxer policy, because that would change the answer silently.
  - Assemblies are documents too: the parts, their occurrences and their
    placements are in the IR. Walking them is not exposed yet.
  """

  alias Cadmpeg.{Document, Error, Native}

  @typedoc "What this build reads, and what it writes."
  @type formats :: %{inputs: [map()], outputs: [String.t()]}

  @doc "Whether the Rust engine is built and loaded in this VM."
  @spec loaded?() :: boolean()
  defdelegate loaded?(), to: Native

  @doc """
  The formats this build reads and writes.

  `:inputs` is the registry's own vocabulary — a format id and the extensions it
  claims — and `:outputs` the ids this build can write.
  """
  @spec formats() :: formats()
  def formats do
    %{
      inputs: Native.inputs() |> Jason.decode!(),
      outputs: Native.outputs() |> Jason.decode!()
    }
  end

  @doc """
  Reads a CAD file into a document, native or STEP.

  Answers the handle and the decode report, both: the report says what was
  transferred and what was lost, and a caller that ignores it has a document of
  unknown fidelity rather than an error.
  """
  @spec open(Path.t()) :: {:ok, Document.t()} | {:error, Error.t()}
  def open(path) when is_binary(path) do
    case Native.open(path) do
      {:ok, {ref, report}} ->
        {:ok, %Document{ref: ref, path: path, report: Jason.decode!(report)}}

      {:error, {code, message}} ->
        {:error, Error.new({code, message})}
    end
  end

  @doc """
  A document from cadmpeg's own JSON.

  The document is parsed, not decoded, so its report is empty — there is nothing
  it could have lost.
  """
  @spec from_json(binary()) :: {:ok, Document.t()} | {:error, Error.t()}
  def from_json(json) when is_binary(json) do
    case Native.from_json(json) do
      {:ok, ref} -> {:ok, %Document{ref: ref, path: "", report: %{}}}
      {:error, {code, message}} -> {:error, Error.new({code, message})}
    end
  end

  @doc """
  Reads `input` and writes the same document as `format` to `output`.

  The two steps `open/1` and `Cadmpeg.Document.write/4` do, in one call, for the
  case that only wants the file.
  """
  @spec convert(Path.t(), String.t(), Path.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def convert(input, format, output, options \\ []) do
    with {:ok, document} <- open(input) do
      Document.write(document, format, output, options)
    end
  end
end
