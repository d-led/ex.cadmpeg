defmodule Cadmpeg.Native do
  @moduledoc """
  The Rust engine, one function per operation it has.

  Nothing here is meant to be called directly: `Cadmpeg` and `Cadmpeg.Document`
  decode the answers, refuse with `Cadmpeg.Error` and keep the handle opaque. An
  operation is listed here, in `native/cadmpeg_nif/src/lib.rs` and in the test
  that calls every one of them, or it does not exist.
  """

  use Rustler, otp_app: :ex_cadmpeg, crate: "cadmpeg_nif"

  @doc "Whether the engine is built and loaded in this VM."
  @spec available() :: boolean()
  def available, do: :erlang.nif_error(:nif_not_loaded)

  # One place lists the engine's operations, and the stubs come from it: a Rust
  # function that is not listed here is not callable, and one that is listed and
  # missing raises on the call rather than answering something invented.
  @spec loaded?() :: boolean()
  def loaded? do
    available()
  rescue
    ErlangError -> false
  end

  @doc "The input formats this build reads, as JSON."
  @spec inputs() :: String.t()
  def inputs, do: :erlang.nif_error(:nif_not_loaded)

  @doc "The output formats this build writes, as JSON."
  @spec outputs() :: String.t()
  def outputs, do: :erlang.nif_error(:nif_not_loaded)

  @doc "The words an output format can be named by."
  @spec vocabulary() :: String.t()
  def vocabulary, do: :erlang.nif_error(:nif_not_loaded)

  @doc "A file opened into a document handle, with its decode report as JSON."
  @spec open(String.t()) ::
          {:ok, {reference(), String.t()}} | {:error, {String.t(), String.t()}}
  def open(_path), do: :erlang.nif_error(:nif_not_loaded)

  @doc "A handle from the document's own JSON."
  @spec from_json(binary()) :: {:ok, reference()} | {:error, {String.t(), String.t()}}
  def from_json(_json), do: :erlang.nif_error(:nif_not_loaded)

  @doc "The document as its versioned JSON."
  @spec to_json(reference()) :: {:ok, String.t()} | {:error, {String.t(), String.t()}}
  def to_json(_document), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Writes the document in `format` to `path`, answering the export report as JSON."
  @spec write(reference(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, {String.t(), String.t()}}
  def write(_document, _format, _path, _target), do: :erlang.nif_error(:nif_not_loaded)
end
