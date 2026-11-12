//! cadmpeg behind one handle: a CAD document, parsed once, as a BEAM resource.
//!
//! The document is `cadmpeg_ir::CadIr` — format neutral, with units, tolerance
//! and flat entity arenas — so a part read from a native format and a part read
//! from STEP are the same kind of value here, and either can be written back in
//! any format this build carries.

use std::fs::File;
use std::path::{Component, Path, PathBuf};

use cadmpeg_container::compound::read_detection_prefix;
use cadmpeg_core::decode::{Companion, Companions, DecodeArena, DecodeContext, View};
use cadmpeg_ir::codec::write::target::TargetRequest;
use cadmpeg_ir::codec::write::EncodeInput;
use cadmpeg_ir::codec::DecodeOptions;
use cadmpeg_ir::report::decode::DecodeReport;
use cadmpeg_ir::{CadIr, SourceFidelity};
use cadmpeg_registry::{
    build_encoder, Format, ForcedInput, InputCatalog, ResolvedSource, DETECTION_PREFIX_LEN,
};
use rustler::{Binary, Resource, ResourceArc};

/// The `(code, message)` pair every refusal carries, so Elixir branches on the
/// code and reads the message.
type Refusal = (String, String);

fn refuse(code: &str, message: impl Into<String>) -> Refusal {
    (code.to_owned(), message.into())
}

/// What a decode answered: the document, and what was lost getting it.
struct Decoded {
    ir: CadIr,
    fidelity: Option<SourceFidelity>,
    /// Empty when the input was already a CADIR document: nothing was decoded,
    /// so there is no decode report to give.
    report: String,
}

/// A document and the fidelity state it was decoded with.
///
/// The fidelity is what tells an encoder which values are exact and which were
/// inferred, so it stays with the document rather than being dropped once the
/// decode report has been read.
struct Document {
    ir: CadIr,
    fidelity: Option<SourceFidelity>,
}

#[rustler::resource_impl]
impl Resource for Document {}

/// The sibling files a native format names by path.
///
/// A `.f3d`, a `.CATPart` or an Inventor assembly keeps parts of itself in files
/// beside it, and a decoder asks for them by relative path. The root is the
/// directory the opened file is in, so a companion cannot be read from outside
/// it.
#[derive(Debug)]
struct Neighbours {
    root: PathBuf,
}

impl Neighbours {
    fn beside(path: &Path) -> Self {
        let root = path.parent().map(Path::to_path_buf).unwrap_or_default();

        Self { root }
    }

    /// Resolves a name the decoder gives against the root.
    fn resolve(&self, anchor: Option<&str>, path: &str) -> Result<PathBuf, String> {
        let base = match anchor {
            Some(anchor) => self.root.join(anchor),
            None => self.root.clone(),
        };

        let base = if base.is_dir() {
            base
        } else {
            base.parent().map(Path::to_path_buf).unwrap_or(base)
        };

        let candidate = normalise(&base.join(path));

        if candidate.starts_with(&self.root) {
            Ok(candidate)
        } else {
            Err(format!("{path}: outside {}", self.root.display()))
        }
    }
}

fn normalise(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();

    for part in path.components() {
        match part {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other.as_os_str()),
        }
    }

    out
}

impl Companions for Neighbours {
    fn open(&self, anchor: Option<&str>, path: &str, max_bytes: u64) -> Result<Companion, String> {
        let file = self.resolve(anchor, path)?;

        let length = std::fs::metadata(&file)
            .map_err(|error| format!("{}: {error}", file.display()))?
            .len();

        if length > max_bytes {
            return Err(format!(
                "{}: {length} bytes is past the limit of {max_bytes}",
                file.display()
            ));
        }

        let bytes =
            std::fs::read(&file).map_err(|error| format!("{}: {error}", file.display()))?;

        Ok(Companion {
            id: file.display().to_string(),
            bytes,
        })
    }

    fn locate(&self, anchor: Option<&str>, path: &str) -> Result<String, String> {
        Ok(self.resolve(anchor, path)?.display().to_string())
    }
}

#[rustler::nif]
fn available() -> bool {
    true
}

/// The input formats this build can read, as JSON: the registry's id and the
/// file extensions it claims.
#[rustler::nif]
fn inputs() -> String {
    let catalog = InputCatalog::with_builtins();

    let rows: Vec<serde_json::Value> = catalog
        .descriptors()
        .map(|descriptor| {
            serde_json::json!({
                "format": descriptor.format_id().to_string(),
                "extensions": descriptor.extensions(),
            })
        })
        .collect();

    serde_json::to_string(&rows).unwrap_or_else(|_| "[]".to_owned())
}

/// The output formats this build can write, as a JSON array of the registry's
/// words.
#[rustler::nif]
fn outputs() -> String {
    let names: Vec<&str> = Format::all().map(|format| format.name().as_str()).collect();

    serde_json::to_string(&names).unwrap_or_else(|_| "[]".to_owned())
}

/// The words an output format can be named by, for a refusal message.
#[rustler::nif]
fn vocabulary() -> String {
    Format::vocabulary()
}

/// Opens a CAD file — native, STEP, or a CADIR document — into the neutral
/// document.
///
/// Answers the handle and the decode report as JSON: what was transferred, and
/// every loss with its reason, so "it opened" and "it opened faithfully" stay
/// different answers. A CADIR document answers an empty report: it was parsed,
/// not decoded.
#[rustler::nif]
fn open(path: String) -> Result<(ResourceArc<Document>, String), Refusal> {
    let path = PathBuf::from(path);

    if !path.is_file() {
        return Err(refuse(
            "unreadable",
            format!("{}: no such file", path.display()),
        ));
    }

    let decoded = decode(&path)?;

    Ok((
        ResourceArc::new(Document {
            ir: decoded.ir,
            fidelity: decoded.fidelity,
        }),
        decoded.report,
    ))
}

fn decode(path: &Path) -> Result<Decoded, Refusal> {
    let neighbours = Neighbours::beside(path);
    let options = DecodeOptions::default();
    let arena = DecodeArena::new();

    let ctx =
        DecodeContext::new(&arena, &options.policy, options.depth).with_companions(&neighbours);

    let mut file =
        File::open(path).map_err(|error| refuse("unreadable", format!("{}: {error}", path.display())))?;

    let mut prefix = read_detection_prefix(&ctx, &mut file, DETECTION_PREFIX_LEN)
        .map_err(|error| refuse("unreadable", format!("{}: {error:?}", path.display())))?;

    let catalog = InputCatalog::with_builtins();

    let resolved = catalog
        .resolve_seekable_source(
            &ctx,
            View::over_retained(&prefix),
            &mut file,
            None::<ForcedInput>,
        )
        .map_err(|error| refuse("unrecognized", format!("{}: {error}", path.display())))?;

    match resolved {
        ResolvedSource::Native { codec, .. } => {
            let format = codec.id().to_string();

            ctx.complete_input(&mut file, &mut prefix)
                .map_err(|error| refuse("unreadable", format!("{format}: {error:?}")))?;

            let result = codec.decode_with_context(&ctx, View::over_retained(&prefix));

            ctx.finish_session()
                .map_err(|error| refuse("internal", format!("{format}: {error:?}")))?;

            let result =
                result.map_err(|failure| refuse("refused", format!("{format}: {failure:?}")))?;

            let (ir, report, fidelity) = result.into_parts();

            Ok(Decoded {
                ir,
                fidelity: Some(fidelity),
                report: report_json(&report),
            })
        }
        ResolvedSource::Cadir => {
            ctx.complete_input(&mut file, &mut prefix)
                .map_err(|error| refuse("unreadable", format!("cadir: {error:?}")))?;

            let text = String::from_utf8(prefix)
                .map_err(|error| refuse("bad_request", format!("cadir: not UTF-8: {error}")))?;

            ctx.finish_session()
                .map_err(|error| refuse("internal", format!("cadir: {error:?}")))?;

            let ir = CadIr::from_json(&text)
                .map_err(|error| refuse("bad_request", format!("cadir: {error}")))?;

            Ok(Decoded {
                ir,
                fidelity: None,
                report: String::new(),
            })
        }
        ResolvedSource::Unrecognized => Err(refuse(
            "unrecognized",
            format!(
                "{}: no codec in this build recognized it; it reads {}",
                path.display(),
                Format::vocabulary()
            ),
        )),
    }
}

fn report_json(report: &DecodeReport) -> String {
    serde_json::to_string(report).unwrap_or_else(|_| "{}".to_owned())
}

/// The document as cadmpeg's versioned JSON, for a caller that would rather
/// keep it than hold the handle.
#[rustler::nif]
fn to_json(document: ResourceArc<Document>) -> Result<String, Refusal> {
    document
        .ir
        .to_canonical_json()
        .map_err(|error| refuse("internal", format!("{error}")))
}

/// A document from cadmpeg's JSON.
#[rustler::nif]
fn from_json(data: Binary) -> Result<ResourceArc<Document>, Refusal> {
    let text = std::str::from_utf8(data.as_slice())
        .map_err(|error| refuse("bad_request", format!("not UTF-8: {error}")))?;

    let ir = CadIr::from_json(text).map_err(|error| refuse("bad_request", format!("{error}")))?;

    Ok(ResourceArc::new(Document { ir, fidelity: None }))
}

/// Writes the document as `format`, to `path`.
///
/// `target` names a dialect inside that format (`"ap242"` for STEP); an empty
/// string lets the encoder choose. Answers the export report as JSON.
#[rustler::nif]
fn write(
    document: ResourceArc<Document>,
    format: String,
    path: String,
    target: String,
) -> Result<String, Refusal> {
    let chosen = Format::from_name(&format)
        .map_err(|error| refuse("bad_request", format!("{format}: {error}")))?
        .ok_or_else(|| {
            refuse(
                "bad_request",
                format!(
                    "{format}: this build cannot write it; it writes {}",
                    Format::vocabulary()
                ),
            )
        })?;

    let encoder = build_encoder(chosen);

    let request = if target.is_empty() {
        TargetRequest::Inherit
    } else {
        TargetRequest::Explicit(&target)
    };

    let input = EncodeInput::new(&document.ir, document.fidelity.as_ref());

    let plan = encoder
        .plan(input, request)
        .map_err(|error| refuse("refused", format!("{}: {error}", chosen.name().as_str())))?;

    let mut file =
        File::create(&path).map_err(|error| refuse("unwritable", format!("{path}: {error}")))?;

    let report = plan
        .write_to(&mut file)
        .map_err(|error| refuse("refused", format!("{path}: {error}")))?;

    serde_json::to_string(&report).map_err(|error| refuse("internal", format!("{error}")))
}

rustler::init!("Elixir.Cadmpeg.Native");
