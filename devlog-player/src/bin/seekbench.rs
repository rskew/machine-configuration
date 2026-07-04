//! Risk check for the whole player: how fast can we seek to an arbitrary time
//! in a cast? Reports cold-load time, index size, and random-seek latency, and
//! verifies snapshot-seek produces the same screen as a full replay from zero.

use std::env;
use std::time::Instant;

use devlog_player::cast::{build_snapshots, seek, Cast};

fn pct(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    let idx = (((sorted.len() - 1) as f64) * p).round() as usize;
    sorted[idx]
}

fn main() {
    let mut args = env::args().skip(1);
    let path = args.next().expect("usage: seekbench <cast> [snap_kib]");
    let snap_bytes = args
        .next()
        .and_then(|s| s.parse::<usize>().ok())
        .map(|k| k * 1024)
        .unwrap_or(256 * 1024);

    let t0 = Instant::now();
    let cast = Cast::load(&path).expect("load cast");
    let parse = t0.elapsed();

    let dur = cast.duration();
    let out_bytes = cast.total_output_bytes();
    println!("file:           {path}");
    println!("parse:          {parse:?}");
    println!("output events:  {}", cast.events.len());
    println!("output bytes:   {:.1} MiB", out_bytes as f64 / 1048576.0);
    println!("cast duration:  {dur:.1} s");
    println!("term size:      {}x{}", cast.header.cols, cast.header.rows);
    println!("snap interval:  {} KiB", snap_bytes / 1024);

    let t1 = Instant::now();
    let snapshots = build_snapshots(&cast, snap_bytes);
    let build = t1.elapsed();
    let index_bytes: usize = snapshots.iter().map(|s| s.dump.len()).sum();
    println!("index build:    {build:?}  (cold full feed)");
    println!("snapshots:      {}", snapshots.len());
    println!("index memory:   {:.1} MiB", index_bytes as f64 / 1048576.0);

    // Correctness: snapshot-seek must equal a full replay from zero.
    let mut ok = true;
    for f in [0.1, 0.37, 0.5, 0.83, 0.99] {
        let target = dur * f;
        let (vt_seek, _) = seek(&cast, &snapshots, target);
        let mut vt_full = avt::Vt::new(cast.header.cols, cast.header.rows);
        for e in &cast.events {
            if e.time > target {
                break;
            }
            vt_full.feed_str(&e.data);
        }
        if vt_seek.text() != vt_full.text() {
            ok = false;
            println!("  MISMATCH at f={f} (t={target:.1}s)");
        }
    }
    println!(
        "correctness:    {}",
        if ok { "snapshot-seek == full-replay" } else { "MISMATCH" }
    );

    // Latency: many jittered random targets across the timeline.
    let n = 500usize;
    let mut times_ms = Vec::with_capacity(n);
    let mut max_replayed = 0usize;
    let mut s: u64 = 0x9E37_79B9_7F4A_7C15;
    let mut rng = || {
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        (s >> 11) as f64 / (1u64 << 53) as f64
    };
    for _ in 0..n {
        let target = dur * rng();
        let t = Instant::now();
        let (_vt, replayed) = seek(&cast, &snapshots, target);
        times_ms.push(t.elapsed().as_secs_f64() * 1000.0);
        max_replayed = max_replayed.max(replayed);
    }
    times_ms.sort_by(|a, b| a.partial_cmp(b).unwrap());
    println!("seeks:          {n} random targets");
    println!("  median:       {:.3} ms", pct(&times_ms, 0.50));
    println!("  p95:          {:.3} ms", pct(&times_ms, 0.95));
    println!("  max:          {:.3} ms", pct(&times_ms, 1.0));
    println!("  max replayed: {max_replayed} events/seek");
}
