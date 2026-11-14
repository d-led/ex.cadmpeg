# Changelog

## 0.1.1

The front page says what this build does, and the how-to said whom it is for.

### Changed

- `README.md` opened with the eleven formats cadmpeg's engine supports and a
  note further down that this build compiles in STEP — so the first thing a
  reader on HexDocs met promised files the package cannot open. It now opens
  with STEP, and the engine's wider set is named as the engine's, with
  `Cadmpeg.formats/0` as the answer for the build in hand.
- The README gained a table of where each other question is answered (the
  document, refusals, the IR, the MCP tools), and everything about changing the
  package moved to `docs/development.md`: the layout, the codec line in
  `Cargo.toml`, the tests, CI and releasing.

## 0.1.0

The first release: cadmpeg on the BEAM, STEP in and out.

### Added

- **The engine.** A Rustler binding of cadmpeg 0.6: input detection through
  `cadmpeg-registry`'s input catalogue, a decode through the codec it selects,
  and the result as one `cadmpeg_ir::CadIr` behind a Rustler resource.
- **The document.** `Cadmpeg.open/1` answers a `Cadmpeg.Document` and the decode
  report: what was transferred, and every loss with its reason. `to_json/1` and
  `from_json/1` are the interchange form, and `write/4` exports the document in
  any format the build carries.
- **`Cadmpeg.convert/4`** — read and write in one call.
- **`Cadmpeg.formats/0`** — what this build reads and writes, taken from the
  registry rather than written down twice.
- **An MCP server.** `mix cadmpeg.mcp` — three tools over stdio: the formats, the
decode report of a file, and a conversion. One document opened once per process.
- **Companions.** A native format that keeps parts of itself in files beside it
  is read against the directory the file is in, and a companion cannot be
  resolved outside it.
- **A translated case.** `test/cadmpeg/upstream_test.exs` carries cadmpeg's
  `writer_pipeline_round_trips_the_full_cube_across_schemas_and_refuses_lossy_strict_output`
  at this binding's level: every STEP schema is written twice, the two writes are
  the same bytes, the file is read back as the schema it was written for, and it
  keeps its bodies and faces.

### Measured

- A STEP part round-trips: `open/1` → `to_json/1` → `from_json/1` → `to_json/1`
  is the same bytes, and `write/4` produces a file that starts with
  `ISO-10303-21`.
