# The document in the middle

What the handle holds, why it is one kind of value whatever the file was, and
where the binding stops.

## One IR, many formats

Each format crate implements `CodecBackend`; the registry decides which one a
file is and hands back its `Codec`. A decode answers a `CadIr` — format neutral,
with units, tolerances and flat entity arenas connected by typed ids — so a part
read from a `.sldprt` and a part read from a `.step` are the same kind of value
here, and either can be written back out in any format the build carries.

The shape is a B-rep: `body → region → shell → face → loop → coedge → edge →
vertex`, with topology referring to geometry carriers rather than nesting them.
Tessellation, appearance, source attributes, native namespaces and
`UnknownRecord`s sit beside it, so a format's own vocabulary survives the round
trip instead of being flattened.

## The three answers a decode gives

- **the document** — the IR;
- **the report** — what was transferred (`container`, `geometry`, …) and every
  loss with its reason, at a severity. A loss that would make the document
  misleading can refuse the decode outright under a strict policy;
- **the fidelity** — which values are byte-exact and which were derived or
  inferred. It stays with the document, because an encoder that does not know
  this cannot say what it is about to lose.

The binding keeps all three: the handle owns the document and its fidelity, and
`Cadmpeg.open/1` answers the report decoded.

## Where the binding stops, and why

- **No policy dial.** cadmpeg's decode takes a policy with resource limits and a
  failure mode. This binding uses the default and exposes neither: a stricter
  policy changes the answer, so it should be asked for by name, and it is not
  askable yet.
- **No editing.** The IR is a document a caller may change, and the draft API
  exists for that; this binding only writes what was read.
- **No assembly walk.** Occurrences and placements are in the IR; a function that
  returns them is not written yet.
- **Companions come from disk.** A native format that names sibling files is read
  against the directory the opened file is in. A document assembled in memory
  therefore cannot be decoded from bytes alone — the file is the interface, which
  is also what cadmpeg says about it.
