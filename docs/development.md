# Working on the package

What a caller needs is in [`README`](readme.html), and what the handle holds is
in [`ir`](ir.html). This page is for changing the package: where the pieces are,
what is compiled in, and how a version is published.

| Path                           | What it is                                                       |
| ------------------------------ | ---------------------------------------------------------------- |
| `lib/cadmpeg.ex`               | the curated surface: what this build reads, `open`, `convert`, `from_json` |
| `lib/cadmpeg/document.ex`      | the handle: `write`, `to_json`, and what it answers about itself  |
| `lib/cadmpeg/error.ex`         | a refusal from the engine, with the code a caller can branch on   |
| `lib/cadmpeg/native.ex`        | the Rustler stubs, and the decode of the engine's flat answers    |
| `lib/cadmpeg/mcp.ex`, `mcp/tools.ex` | the Model Context Protocol server and its three tools       |
| `lib/mix/tasks/cadmpeg.mcp.ex` | `mix cadmpeg.mcp`, which an MCP client launches                   |
| `native/cadmpeg_nif/`          | the Rust side: `src/lib.rs` and `Cargo.toml`, where the codecs are chosen |
| `test/cadmpeg/upstream_test.exs` | the cases translated from cadmpeg's own tests, and the ones that are not, and why |
| `docs/ir.md`                   | the document in the middle, and where the binding stops           |

## The codecs are build-time choices

cadmpeg's codecs are Rust features, and `native/cadmpeg_nif/Cargo.toml` is the
only place one is chosen:

```toml
cadmpeg-registry = { version = "=0.6.11", default-features = false, features = ["step"] }
```

Each codec is its own crate, so a build carries only what it lists — and
`Cadmpeg.formats/0` answers from the engine rather than from a constant here, so
a build that carries two codecs says two. Adding one is that line plus a fixture
to read with it; there is nothing to change in `lib/`.

## Tests

`mix test` builds the Rust engine and runs the suite against `test/fixtures`:
behaviour through the curated surface, the decode and export reports, the MCP
tools, and `test/cadmpeg/upstream_test.exs`, which is the record of what was
translated from cadmpeg's own tests, one case for one, and names the cases that
were not translated and why.

`scripts/quality.sh` is what CI runs; run it before calling a change done.

## CI and publishing

`.github/workflows/ci.yml` proves a commit and `.github/workflows/release.yml`
publishes a tag to Hex, which needs the `HEX_API_KEY` secret on this repository.

Nothing is published from a branch: CI proves a commit, a tag says it is a
version. The version lives in `mix.exs` (and the dependency line in the README);
the release workflow refuses a tag that disagrees with it.

Then watch the release run: the package and the documentation are staged for
approval on Hex separately, so `mix hex.publish` succeeding is not the same as
being installable.
