# ex_cadmpeg

An Elixir wrapper of [cadmpeg](https://github.com/cadmpeg/cadmpeg) to bring
native CAD files onto the BEAM: SolidWorks `.sldprt`, CATIA `.CATPart`, Inventor
`.ipt`/`.iam`, Creo, NX, Fusion `.f3d`, FreeCAD `.FCStd`, Rhino `.3dm`, IGES,
STEP, Creo View `.pvz` and OpenUSD read into one format-neutral CAD document,
and that document written back out. Wrapped via rustler; the engine underneath
is pure Rust, so there is no vendor SDK, no OpenCascade and no CAD system
installed anywhere.

This build compiles in the STEP codec, so it reads and writes STEP — "Formats are
compiled in" below says how a build carries another one.

```elixir
{:ok, document} = Cadmpeg.open("bracket.step")

{:ok, report} = Cadmpeg.Document.write(document, "step", "bracket-strict.step")
```

`report` is the export report: what the encoder wrote, and what it could not
carry. A conversion that loses something says so.

Everything is in the file's own units, in its own coordinates, and the same file
always gives the same document.

## What it answers

| Question | Call |
| --- | --- |
| What does this build read and write? | `Cadmpeg.formats/0` |
| Read a part, and how faithfully? | `Cadmpeg.open/1` — the handle and the decode report |
| Convert it | `Cadmpeg.convert/4`, or `Cadmpeg.Document.write/4` |
| Keep it without the handle | `Cadmpeg.Document.to_json/1`, `Cadmpeg.from_json/1` |

A document is parsed **once**: `open/1` answers a handle and every later call
takes it, so asking three questions about one part reads it once. The handle is a
Rust resource — it serves every process on its node and cannot be sent to another
node, because the document is local.

## Formats are compiled in

cadmpeg's codecs are Rust features. This package compiles in the STEP codec, so
`formats/0` lists STEP as an input and as an output and does not pretend to read
a `.sldprt`. Turning on another codec is a line in
`native/cadmpeg_nif/Cargo.toml`:

```toml
cadmpeg-registry = { version = "=0.6.11", default-features = false, features = ["step", "sldprt"] }
```

Each codec is its own crate, so a build carries only the formats it needs. Which
formats a build has is a fact about the binary in the VM, not a promise.

## As an MCP server

`mix cadmpeg.mcp` speaks the Model Context Protocol over stdio, so an assistant
can ask about a file directly:

```json
{"mcpServers": {"cadmpeg": {"command": "mix", "args": ["cadmpeg.mcp"]}}}
```

Three tools: `cadmpeg_formats` — what this build reads and writes —
`cadmpeg_inspect`, which answers the decode report rather than just "it
opened", and `cadmpeg_convert`, which writes the file you name and reports what
the target could not carry.

## Install

```elixir
def deps do
  [{:ex_cadmpeg, "~> 0.1"}]
end
```

The Rust engine is compiled when the dependency is: **building wants a Rust
toolchain** (1.88 or later, which is what cadmpeg itself requires), and running
wants none.

## Limits, said out loud

- The document is read-only here. cadmpeg's IR can be edited; this binding does
  not expose editing yet, and `to_json/1` is the way to a document a caller can
  change.
- "It opened" is not "it opened faithfully". cadmpeg scores each format on a
  ladder, and the decode report carries the losses; a caller that ignores the
  report has a document of unknown fidelity rather than an error.
- Assemblies are documents too — parts, occurrences and placements are in the
  IR — but walking them is not exposed yet.
- A refusal is not retried at a laxer policy. A stricter or looser policy changes
  the answer, so `Cadmpeg.Error` says what was refused and the caller decides.

## Licence

MPL-2.0 (`LICENSE`). The engine it binds is Apache-2.0 and stays a dependency;
`NOTICE` says what came from where.
