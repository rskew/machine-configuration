//! Reads ActivityWatch events straight from the aw-server-rust sqlite db.
//!
//! Schema: `events(bucketrow, starttime, endtime, data)` joined to
//! `buckets(id, name, type)`. Times are epoch *nanoseconds*; we expose epoch
//! seconds. We don't go through the REST API so the player works offline and
//! without the server running.

use std::collections::HashMap;
use std::path::Path;

use rusqlite::Connection;
use serde_json::Value;

#[derive(Clone)]
pub struct AwEvent {
    pub start: f64, // epoch seconds
    pub end: f64,
    pub data: Value,
}

impl AwEvent {
    /// Convenience: a string field from the event's JSON data.
    pub fn field(&self, key: &str) -> Option<&str> {
        self.data.get(key).and_then(Value::as_str)
    }
}

/// Which timeline lane an AW bucket belongs to, by name prefix.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Lane {
    Window,
    Web,
    Afk,
    Workspace,
}

pub fn lane_for_bucket(name: &str) -> Option<Lane> {
    if name.starts_with("aw-watcher-window") {
        Some(Lane::Window)
    } else if name.starts_with("aw-watcher-web") {
        Some(Lane::Web)
    } else if name.starts_with("aw-watcher-afk") {
        Some(Lane::Afk)
    } else if name.starts_with("aw-watcher-workspace") {
        Some(Lane::Workspace)
    } else {
        None
    }
}

/// All AW events grouped by lane, each lane sorted by start time.
pub struct AwData {
    pub lanes: HashMap<Lane, Vec<AwEvent>>,
}

impl AwData {
    pub fn get(&self, lane: Lane) -> &[AwEvent] {
        self.lanes.get(&lane).map(Vec::as_slice).unwrap_or(&[])
    }
}

pub fn load(db: &Path) -> rusqlite::Result<AwData> {
    let conn = Connection::open(db)?;
    let mut stmt = conn.prepare(
        "SELECT b.name, e.starttime, e.endtime, e.data \
         FROM events e JOIN buckets b ON e.bucketrow = b.id \
         ORDER BY e.starttime",
    )?;

    let rows = stmt.query_map([], |row| {
        let name: String = row.get(0)?;
        let start_ns: i64 = row.get(1)?;
        let end_ns: i64 = row.get(2)?;
        let data_str: String = row.get(3)?;
        Ok((name, start_ns, end_ns, data_str))
    })?;

    let mut lanes: HashMap<Lane, Vec<AwEvent>> = HashMap::new();
    for row in rows {
        let (name, start_ns, end_ns, data_str) = row?;
        let Some(lane) = lane_for_bucket(&name) else {
            continue;
        };
        let data: Value = serde_json::from_str(&data_str).unwrap_or(Value::Null);
        lanes.entry(lane).or_default().push(AwEvent {
            start: start_ns as f64 / 1e9,
            end: end_ns as f64 / 1e9,
            data,
        });
    }
    Ok(AwData { lanes })
}
