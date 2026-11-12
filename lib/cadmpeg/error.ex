defmodule Cadmpeg.Error do
  @moduledoc """
  A refusal from the engine, with the code a caller can branch on.

  The codes are this binding's own, one per kind of refusal:

    * `"unreadable"` — the file is not there, or cannot be opened;
    * `"unrecognized"` — no codec in this build recognized the bytes; the
      message lists what it does read;
    * `"refused"` — a codec recognized the file and refused to transfer it
      faithfully: a strict-policy refusal, or an export that cannot carry what
      the document holds;
    * `"bad_request"` — the question was malformed: a format word this build
      cannot write, a document that is not its JSON;
    * `"unwritable"` — the output path cannot be created;
    * `"internal"` — a report that could not be serialised.

  A refusal is a *value*, not an exception: a call that cannot answer still
  answers, and says what to try next.
  """

  defexception [:code, :message]

  @type t :: %__MODULE__{code: String.t(), message: String.t()}

  @impl true
  def message(%__MODULE__{code: code, message: message}), do: "#{code}: #{message}"

  @doc "A refusal, from the engine's `{code, message}` pair."
  @spec new({String.t(), String.t()}) :: t()
  def new({code, message}), do: %__MODULE__{code: code, message: message}
end
