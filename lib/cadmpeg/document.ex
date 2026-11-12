defmodule Cadmpeg.Document do
  @moduledoc """
  A CAD document, parsed once: cadmpeg's format-neutral CAD IR behind a handle.

  `Cadmpeg.open/1` reads a file and answers one of these. Everything else takes
  it, so a part is parsed once however many questions follow, and a part read
  from a native format and a part read from STEP are the same kind of value.

  The handle is a Rust resource: it serves every process on its node at once and
  cannot be sent to another node, which is the honest boundary — the document is
  local.

  ## Fields

    * `:ref` — the engine's handle. Opaque; nothing in this package reads it.
    * `:path` — the file it was read from, for a message that has to say which.
    * `:report` — the decode report, decoded: what was transferred, and every
      loss with its reason. Empty for a document that came from its own JSON,
      because nothing was decoded.
  """

  alias Cadmpeg.{Error, Native}

  @enforce_keys [:ref, :path, :report]
  defstruct [:ref, :path, :report]

  @type t :: %__MODULE__{ref: reference(), path: String.t(), report: map()}

  @doc """
  The document as cadmpeg's versioned JSON.

  This is the interchange form: it round-trips through `Cadmpeg.from_json/1`
  without the handle, and it is what a caller keeps on disk to read the document
  later without the file it came from.
  """
  @spec to_json(t()) :: {:ok, String.t()} | {:error, Error.t()}
  def to_json(%__MODULE__{ref: ref}), do: answer(Native.to_json(ref))

  @doc """
  Writes the document as `format`, to `path`.

  Formats are the engine's own words — `"step"`, `"cadir"` for the document's own
  JSON, which `"json"` is also accepted for — and `Cadmpeg.formats/0` says which
  this build carries. `:target` names a dialect
  inside the format (`"ap242"` for STEP); without one the encoder chooses, which
  for a part that came from STEP keeps the dialect it was read in.

  Answers the export report: what the encoder wrote, and what it could not
  carry, so a lossy conversion says so rather than looking successful.
  """
  @spec write(t(), String.t(), Path.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def write(%__MODULE__{ref: ref}, format, path, options \\ []) do
    target = Keyword.get(options, :target, "")

    ref
    |> Native.write(format, path, target)
    |> answer()
    |> decode_report()
  end

  defp answer({:ok, json}), do: {:ok, json}
  defp answer({:error, {code, message}}), do: {:error, Error.new({code, message})}

  defp decode_report({:ok, json}), do: {:ok, Jason.decode!(json)}
  defp decode_report({:error, error}), do: {:error, error}
end
