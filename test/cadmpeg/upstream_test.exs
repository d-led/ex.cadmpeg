defmodule Cadmpeg.UpstreamTest do
  @moduledoc """
  Cases translated from cadmpeg's own high-level tests.

  cadmpeg's `crates/*/src/integration_tests.rs` drive the codec and encoder APIs
  directly — `StepCodec::plan`, `ExportPlan::write_to`, `Codec::decode` — which
  is the level this binding exposes as `Cadmpeg.open/1` and
  `Cadmpeg.Document.write/4`. A case here is one case there: the name says which.

  ## What is not translated, and why

  `writer_pipeline_round_trips_the_full_cube_across_schemas_and_refuses_lossy_strict_output`
  has three halves. Two are here. The third — a decode under a strict policy that
  refuses a lossy transfer — is a decode *option* this binding does not expose,
  so a test of it would be testing a dial that does not exist here.

  The sibling cases in that file are pipeline-internal: they compose reader
  sub-modules over synthesised exchanges, which is cadmpeg's business and not
  something a caller of this binding can reach.
  """

  use ExUnit.Case, async: true

  alias Cadmpeg.Document

  @fixture "test/fixtures/golden_simple_through_hole.step"

  # The encoder's own target ids, in the order the upstream case walks the
  # schemas. The id carries the format's namespace and hyphenates the edition,
  # and it is also the dialect the written file is read back as.
  @schemas ~w(ap203-e1 ap203-e2 ap214 ap242-e1 ap242-e2 ap242-e3)

  setup_all do
    {:ok, document} = Cadmpeg.open(@fixture)
    {:ok, json} = Document.to_json(document)

    %{document: document, ir: Jason.decode!(json)}
  end

  defp faces(ir), do: length(ir["model"]["faces"] || [])
  defp bodies(ir), do: length(ir["model"]["bodies"] || [])

  describe "cadmpeg-codec-step integration_tests.rs" do
    # Translated from the first half of
    # `writer_pipeline_round_trips_the_full_cube_across_schemas_and_refuses_lossy_strict_output`:
    # every schema is written, the same write twice is the same bytes, the bytes
    # are recognised as the schema they were written for, and reading them back
    # keeps the document's bodies and faces.
    @tag :tmp_dir
    test "writing across schemas is deterministic and reads back", %{
      document: document,
      ir: ir,
      tmp_dir: dir
    } do
      for schema <- @schemas do
        out = Path.join(dir, "#{schema}.step")

        assert {:ok, _report} =
                 Document.write(document, "step", Path.join(dir, "#{schema}-1.step"),
                   target: schema
                 )

        assert {:ok, _report} =
                 Document.write(document, "step", Path.join(dir, "#{schema}-2.step"),
                   target: schema
                 )

        first = File.read!(Path.join(dir, "#{schema}-1.step"))
        second = File.read!(Path.join(dir, "#{schema}-2.step"))

        assert first == second, "#{schema}: the same write twice produced different bytes"
        File.write!(out, first)

        assert {:ok, round_tripped} = Cadmpeg.open(out)

        assert round_tripped.report["identity"]["dialects"]["primary"]["dialect"] ==
                 "step:#{schema}",
               "#{schema}: the file was not read as the schema it was written for"

        assert {:ok, round_tripped_json} = Document.to_json(round_tripped)
        read_back = Jason.decode!(round_tripped_json)

        assert bodies(read_back) == bodies(ir), "#{schema}: bodies changed in the round trip"
        assert faces(read_back) == faces(ir), "#{schema}: faces changed in the round trip"
      end
    end

    # Translated from the same case's refusal: a schema this encoder cannot
    # synthesize is refused by name, with the ones it can carry in the message.
    @tag :tmp_dir
    test "a schema the encoder cannot synthesize is refused, and the ones it can are listed",
         %{document: document, tmp_dir: dir} do
      assert {:error, error} =
               Document.write(document, "step", Path.join(dir, "nope.step"), target: "ap242")

      assert error.code == "refused"
      assert error.message =~ "not a target this encoder can synthesize"
      assert error.message =~ "step:ap242-e1"
    end
  end
end
