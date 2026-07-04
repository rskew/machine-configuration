//! asciinema v2 cast loading + arbitrary-time seek.
//!
//! A cast is a stream of output *deltas*, so the screen at time T is the result
//! of feeding every output event in `[0, T]` into a terminal emulator. Replaying
//! from zero on every scrub is O(events); to make seeking cheap we periodically
//! snapshot the emulator (`Vt::dump`) so a seek replays at most one snapshot
//! interval of output.

use std::fs::File;
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use avt::Vt;
use serde_json::Value;

/// Lightweight cast metadata (start/end epoch + size) read without parsing the
/// whole file — the header is the first line, the end time is recovered by
/// tailing the file. Lets the UI populate the timeline before loading 100+ MB.
pub struct CastMeta {
    pub path: PathBuf,
    pub start: f64,
    pub end: f64,
    pub cols: usize,
    pub rows: usize,
    /// First command the user ran in the recording, used as a one-line
    /// "what was this session for" hint in the terminal rail.
    pub first_command: Option<String>,
}

impl CastMeta {
    pub fn label(&self) -> String {
        self.path
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default()
    }
}

pub fn cast_meta(path: impl AsRef<Path>) -> std::io::Result<CastMeta> {
    let path = path.as_ref().to_path_buf();
    let mut f = File::open(&path)?;

    let mut header_line = String::new();
    BufReader::new(&f).read_line(&mut header_line)?;
    let h: Value = serde_json::from_str(header_line.trim()).expect("invalid cast header");
    let timestamp = h["timestamp"].as_f64().unwrap_or(0.0);
    let cols = h["width"].as_u64().unwrap_or(80) as usize;
    let rows = h["height"].as_u64().unwrap_or(24) as usize;

    // Tail the file and recover the last event's offset.
    let len = f.metadata()?.len();
    let tail = len.min(65536);
    f.seek(SeekFrom::Start(len - tail))?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf)?;
    let text = String::from_utf8_lossy(&buf);
    let last_offset = text
        .lines()
        .rev()
        .filter_map(|l| {
            let l = l.trim();
            if !l.starts_with('[') {
                return None;
            }
            let c = l.find(',')?;
            l[1..c].trim().parse::<f64>().ok()
        })
        .next()
        .unwrap_or(0.0);

    let first_command = extract_first_command(&path, cols, rows);

    Ok(CastMeta {
        path,
        start: timestamp,
        end: timestamp + last_offset,
        cols,
        rows,
        first_command,
    })
}

/// Reopen the cast and simulate the first few seconds of output through avt.
/// Watch for the cursor row to advance — that's the moment the user pressed
/// Enter — and return the line at the previous row, stripped of its prompt.
fn extract_first_command(path: &Path, cols: usize, rows: usize) -> Option<String> {
    let file = File::open(path).ok()?;
    let mut reader = BufReader::new(file);
    let mut line = String::new();
    reader.read_line(&mut line).ok()?; // discard the JSON header

    let mut vt = Vt::new(cols, rows);
    let mut prev_lines: Vec<String> = Vec::new();
    let mut prev_row: usize = 0;
    let mut fed_bytes = 0usize;
    let mut event_count = 0usize;

    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) | Err(_) => break,
            _ => {}
        }
        let trimmed = line.trim_end();
        if trimmed.is_empty() {
            continue;
        }
        let v: Value = match serde_json::from_str(trimmed) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let arr = match v.as_array() {
            Some(a) if a.len() >= 3 => a,
            _ => continue,
        };
        if arr[1].as_str() != Some("o") {
            continue;
        }
        let data = arr[2].as_str().unwrap_or("");
        let time = arr[0].as_f64().unwrap_or(0.0);

        vt.feed_str(data);
        fed_bytes += data.len();
        event_count += 1;
        let cur_row = vt.cursor().row;

        if event_count > 1 && cur_row > prev_row {
            if let Some(prev) = prev_lines.get(prev_row) {
                let text = prev.trim_end();
                let stripped = strip_prompt(text);
                if !stripped.is_empty() {
                    return Some(stripped.to_string());
                }
            }
        }

        // Bound the work so we don't read huge casts at metadata time.
        if fed_bytes > 65536 || event_count > 400 || time > 10.0 {
            break;
        }

        prev_lines = vt.view().map(|l| l.text()).collect();
        prev_row = cur_row;
    }
    None
}

/// Best-effort: strip the shell prompt off the front of a typed command line.
/// Looks for the last "$ ", "> ", or "# "; falls back to leading whitespace.
fn strip_prompt(line: &str) -> &str {
    for marker in ["$ ", "> ", "# ", "% "] {
        if let Some(idx) = line.rfind(marker) {
            return line[idx + marker.len()..].trim();
        }
    }
    line.trim_start()
}

pub struct Header {
    pub cols: usize,
    pub rows: usize,
    /// Epoch seconds of the cast's start — absolute UTC = `timestamp + event.time`.
    pub timestamp: f64,
}

pub struct OutEvent {
    /// Offset in seconds from the cast start.
    pub time: f64,
    pub data: String,
}

pub struct Cast {
    pub header: Header,
    /// Output events only ("o"); input/marker/resize events are dropped since
    /// only output drives the visible screen.
    pub events: Vec<OutEvent>,
}

impl Cast {
    pub fn load(path: impl AsRef<Path>) -> std::io::Result<Cast> {
        let file = File::open(path)?;
        let mut reader = BufReader::new(file);

        let mut header_line = String::new();
        reader.read_line(&mut header_line)?;
        let h: Value =
            serde_json::from_str(header_line.trim()).expect("invalid cast header");
        let header = Header {
            cols: h["width"].as_u64().expect("cast header missing width") as usize,
            rows: h["height"].as_u64().expect("cast header missing height") as usize,
            timestamp: h["timestamp"].as_f64().unwrap_or(0.0),
        };

        let mut events = Vec::new();
        let mut line = String::new();
        loop {
            line.clear();
            if reader.read_line(&mut line)? == 0 {
                break;
            }
            let trimmed = line.trim_end();
            if trimmed.is_empty() {
                continue;
            }
            let v: Value = match serde_json::from_str(trimmed) {
                Ok(v) => v,
                Err(_) => continue,
            };
            let arr = match v.as_array() {
                Some(a) if a.len() >= 3 => a,
                _ => continue,
            };
            if arr[1].as_str() != Some("o") {
                continue;
            }
            events.push(OutEvent {
                time: arr[0].as_f64().unwrap_or(0.0),
                data: arr[2].as_str().unwrap_or("").to_string(),
            });
        }
        Ok(Cast { header, events })
    }

    pub fn duration(&self) -> f64 {
        self.events.last().map(|e| e.time).unwrap_or(0.0)
    }

    pub fn total_output_bytes(&self) -> usize {
        self.events.iter().map(|e| e.data.len()).sum()
    }
}

pub struct Snapshot {
    pub time: f64,
    /// Index of the first event *after* this snapshot was taken.
    pub event_idx: usize,
    pub dump: String,
}

/// Feed the whole cast once, snapshotting roughly every `snap_bytes` of output
/// so any seek replays at most that many bytes.
pub fn build_snapshots(cast: &Cast, snap_bytes: usize) -> Vec<Snapshot> {
    let mut vt = Vt::new(cast.header.cols, cast.header.rows);
    let mut snapshots = vec![Snapshot {
        time: 0.0,
        event_idx: 0,
        dump: vt.dump(),
    }];
    let mut since = 0usize;
    for (i, e) in cast.events.iter().enumerate() {
        vt.feed_str(&e.data);
        since += e.data.len();
        if since >= snap_bytes {
            snapshots.push(Snapshot {
                time: e.time,
                event_idx: i + 1,
                dump: vt.dump(),
            });
            since = 0;
        }
    }
    snapshots
}

/// Reconstruct the screen at or before `target` seconds (offset from cast start).
/// Returns the emulator and how many events were replayed from the snapshot.
pub fn seek(cast: &Cast, snapshots: &[Snapshot], target: f64) -> (Vt, usize) {
    let idx = snapshots
        .partition_point(|s| s.time <= target)
        .saturating_sub(1);
    let snap = &snapshots[idx];
    let mut vt = Vt::new(cast.header.cols, cast.header.rows);
    vt.feed_str(&snap.dump);
    let mut replayed = 0usize;
    for e in &cast.events[snap.event_idx..] {
        if e.time > target {
            break;
        }
        vt.feed_str(&e.data);
        replayed += 1;
    }
    (vt, replayed)
}

/// A cast plus its seek index, owning everything so it can live in the UI state
/// without self-referential lifetimes.
pub struct Recording {
    pub path: PathBuf,
    pub cast: Cast,
    pub snapshots: Vec<Snapshot>,
}

impl Recording {
    pub fn load(path: impl AsRef<Path>, snap_bytes: usize) -> std::io::Result<Recording> {
        let path = path.as_ref().to_path_buf();
        let cast = Cast::load(&path)?;
        let snapshots = build_snapshots(&cast, snap_bytes);
        Ok(Recording {
            path,
            cast,
            snapshots,
        })
    }

    pub fn start_epoch(&self) -> f64 {
        self.cast.header.timestamp
    }

    pub fn end_epoch(&self) -> f64 {
        self.cast.header.timestamp + self.cast.duration()
    }

    pub fn cols(&self) -> usize {
        self.cast.header.cols
    }

    pub fn rows(&self) -> usize {
        self.cast.header.rows
    }

    /// Screen state at an absolute epoch time. Returns None if the epoch is
    /// outside this recording's range.
    pub fn screen_at_epoch(&self, epoch: f64) -> Option<Vt> {
        if epoch < self.start_epoch() || epoch > self.end_epoch() + 1.0 {
            return None;
        }
        let off = (epoch - self.start_epoch()).max(0.0);
        Some(seek(&self.cast, &self.snapshots, off).0)
    }

    /// Filename without extension, e.g. "2026-05-28T02-41-25Z".
    pub fn label(&self) -> String {
        self.path
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default()
    }
}
