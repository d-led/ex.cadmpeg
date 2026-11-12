# Changelog

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

### Measured

- A STEP part round-trips: `open/1` → `to_json/1` → `from_json/1` → `to_json/1`
  is the same bytes, and `write/4` produces a file that starts with
  `ISO-10303-21`.
