defmodule CadmpegTest do
  @moduledoc """
  What the binding answers, not how the engine does it. Every operation the NIF
  exposes is called here, so a function that stops existing fails a test rather
  than a call.
  """

  use ExUnit.Case, async: true

  alias Cadmpeg.{Document, Error}

  @fixture "test/fixtures/golden_simple_through_hole.step"

  describe "what this build carries" do
    test "the engine is loaded" do
      assert Cadmpeg.loaded?()
    end

    test "it reads STEP and writes STEP and its own JSON" do
      %{inputs: inputs, outputs: outputs} = Cadmpeg.formats()

      assert Enum.any?(inputs, &(&1["format"] == "step"))
      assert "step" in outputs
      assert "cadir" in outputs
    end

    test "every input format names the extensions it claims" do
      %{inputs: inputs} = Cadmpeg.formats()

      assert inputs != []
      assert Enum.all?(inputs, &(is_list(&1["extensions"]) and &1["extensions"] != []))
    end
  end

  describe "opening a part" do
    test "answers the document and the report of how it was read" do
      assert {:ok, %Document{} = document} = Cadmpeg.open(@fixture)

      assert document.path == @fixture
      assert is_map(document.report)
      assert map_size(document.report) > 0
    end

    test "the report says what was transferred, not just that it worked" do
      {:ok, document} = Cadmpeg.open(@fixture)

      # cadmpeg reports a transfer verb, so "opened" and "opened faithfully" stay
      # different answers.
      assert Map.has_key?(document.report, "transfer") or
               Map.has_key?(document.report, "losses")
    end

    test "a missing file is a refusal with a code, not a crash" do
      assert {:error, %Error{code: "unreadable"}} = Cadmpeg.open("test/fixtures/absent.step")
    end

    @tag :tmp_dir
    test "bytes no codec recognizes are refused by name", %{tmp_dir: dir} do
      path = Path.join(dir, "notes.sldprt")
      File.write!(path, "this is not a CAD file")

      assert {:error, %Error{code: "unrecognized", message: message}} = Cadmpeg.open(path)
      assert message =~ "no codec"
    end
  end

  describe "the document's own JSON" do
    test "round-trips, and the second form is the same document" do
      {:ok, document} = Cadmpeg.open(@fixture)

      assert {:ok, json} = Document.to_json(document)
      assert {:ok, restored} = Cadmpeg.from_json(json)
      assert {:ok, ^json} = Document.to_json(restored)
    end

    test "a parsed document has no report, because nothing was decoded" do
      {:ok, document} = Cadmpeg.open(@fixture)
      {:ok, json} = Document.to_json(document)
      {:ok, restored} = Cadmpeg.from_json(json)

      assert restored.report == %{}
    end

    test "JSON that is not a document is refused as a bad request" do
      assert {:error, %Error{code: "bad_request"}} = Cadmpeg.from_json(~s({"nope": true}))
    end
  end

  describe "writing a document out" do
    @tag :tmp_dir
    test "writes STEP, which is a STEP file when it lands", %{tmp_dir: dir} do
      {:ok, document} = Cadmpeg.open(@fixture)
      out = Path.join(dir, "again.step")

      assert {:ok, report} = Document.write(document, "step", out)
      assert File.exists?(out)
      assert File.read!(out) =~ "ISO-10303-21"
      assert is_map(report)
    end

    @tag :tmp_dir
    test "convert/4 is the two steps in one call", %{tmp_dir: dir} do
      out = Path.join(dir, "converted.step")

      assert {:ok, _report} = Cadmpeg.convert(@fixture, "step", out)
      assert File.read!(out) =~ "ISO-10303-21"
    end

    @tag :tmp_dir
    test "a format this build cannot write is named, and the writes it has are listed",
         %{tmp_dir: dir} do
      {:ok, document} = Cadmpeg.open(@fixture)

      assert {:error, %Error{code: "bad_request", message: message}} =
               Document.write(document, "usd", Path.join(dir, "out.usda"))

      assert message =~ "cannot write"
      assert message =~ "step"
    end

    @tag :tmp_dir
    test "an output path that cannot be created is refused", %{tmp_dir: dir} do
      {:ok, document} = Cadmpeg.open(@fixture)

      assert {:error, %Error{code: "unwritable"}} =
               Document.write(document, "step", Path.join([dir, "absent", "out.step"]))
    end
  end
end
