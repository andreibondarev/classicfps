mod bitreader;
mod bsp;
mod delta;
mod demo;
mod entity;
mod events;
mod mdl;
mod netmsg;
mod types;

use types::*;
use wasm_bindgen::prelude::*;

#[cfg(target_arch = "wasm32")]
#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    pub fn log(s: &str);
}

#[cfg(not(target_arch = "wasm32"))]
pub fn log(s: &str) {
    println!("{}", s);
}

#[macro_export]
macro_rules! console_log {
    ($($t:tt)*) => ($crate::log(&format!($($t)*)))
}

/// Native-only: parse a demo and return the distinct player names that appear
/// in timeline entries (for verifying entity->name mapping).
#[cfg(not(target_arch = "wasm32"))]
pub fn debug_distinct_entity_names(data: &[u8]) -> Vec<String> {
    let mut parser = demo::DemoParser::new(data);
    let parsed = parser.parse().expect("demo parse failed");
    let timeline = demo::build_timeline(&parsed, 0.05, data);
    let mut names: Vec<String> = timeline
        .entries
        .iter()
        .flat_map(|e| e.players.iter().map(|p| p.name.clone()))
        .collect();
    names.sort();
    names.dedup();
    names
}

/// Native-only: parse and return (duration, entry count, distinct names,
/// max |coordinate|) for corpus invariant checks. Timeline times are checked
/// for monotonicity here as well.
#[cfg(not(target_arch = "wasm32"))]
pub fn debug_timeline_stats(data: &[u8]) -> Result<(f32, usize, Vec<String>, f32), String> {
    let mut parser = demo::DemoParser::new(data);
    let parsed = parser.parse()?;
    let timeline = demo::build_timeline(&parsed, 0.05, data);

    let mut names: Vec<String> = Vec::new();
    let mut max_abs = 0f32;
    let mut last_time = f32::MIN;
    for entry in &timeline.entries {
        if entry.time < last_time {
            return Err(format!(
                "non-monotonic time {} after {}",
                entry.time, last_time
            ));
        }
        last_time = entry.time;
        for p in &entry.players {
            if !names.contains(&p.name) {
                names.push(p.name.clone());
            }
            for v in [p.origin.x, p.origin.y, p.origin.z] {
                if v.is_finite() {
                    max_abs = max_abs.max(v.abs());
                }
            }
        }
    }
    Ok((timeline.duration, timeline.entries.len(), names, max_abs))
}

/// Native-only: bbox of weapon merged onto player skeleton vs raw
#[cfg(not(target_arch = "wasm32"))]
pub fn debug_attach_bbox(
    player: &[u8],
    weapon: &[u8],
) -> ((f32, f32, f32), (f32, f32, f32), (f32, f32, f32), usize) {
    let raw = mdl::parse_mdl(weapon).expect("weapon parse");
    let (merged, anims) = mdl::parse_mdl_attached(player, weapon).expect("attach parse");
    let bbox = |pos: &[f32]| {
        let mut c = (0f32, 0f32, 0f32);
        for i in (0..pos.len()).step_by(3) {
            c.0 += pos[i];
            c.1 += pos[i + 1];
            c.2 += pos[i + 2];
        }
        let n = (pos.len() / 3).max(1) as f32;
        (c.0 / n, c.1 / n, c.2 / n)
    };
    let n = merged.positions.len();
    let frame0 = anims
        .first()
        .map(|a| bbox(&a.data[..n.min(a.data.len())]))
        .unwrap_or((0.0, 0.0, 0.0));
    (
        bbox(&raw.positions),
        bbox(&merged.positions),
        frame0,
        anims.len(),
    )
}

#[cfg(not(target_arch = "wasm32"))]
pub fn debug_mdl_animation_labels(data: &[u8]) -> Vec<String> {
    mdl::parse_mdl_animated(data)
        .expect("model animation parse")
        .1
        .into_iter()
        .map(|animation| animation.name)
        .collect()
}

/// Native-only: validate a primary GoldSrc studio model without panicking.
#[cfg(not(target_arch = "wasm32"))]
pub fn debug_mdl_valid(data: &[u8]) -> bool {
    std::panic::catch_unwind(|| mdl::parse_mdl(data).is_ok()).unwrap_or(false)
}

/// Native-only: shot-track count
#[cfg(not(target_arch = "wasm32"))]
pub fn debug_shot_count(data: &[u8]) -> usize {
    let mut parser = demo::DemoParser::new(data);
    let parsed = parser.parse().expect("demo parse failed");
    demo::build_timeline(&parsed, 0.05, data).shot_track.len()
}

/// Native-only: event counts after round normalization.
#[cfg(not(target_arch = "wasm32"))]
pub fn debug_event_counts(data: &[u8]) -> std::collections::BTreeMap<String, usize> {
    let mut parser = demo::DemoParser::new(data);
    let parsed = parser.parse().expect("demo parse failed");
    let timeline = demo::build_timeline(&parsed, 0.05, data);
    let mut counts = std::collections::BTreeMap::new();
    for event in timeline.events {
        *counts.entry(format!("{:?}", event.event_type)).or_default() += 1;
    }
    counts
}

/// Native-only: count object-track samples per kind
#[cfg(not(target_arch = "wasm32"))]
pub fn debug_obj_track_counts(data: &[u8]) -> std::collections::HashMap<u8, usize> {
    let mut parser = demo::DemoParser::new(data);
    let parsed = parser.parse().expect("demo parse failed");
    let timeline = demo::build_timeline(&parsed, 0.05, data);
    let mut counts: std::collections::HashMap<u8, usize> = Default::default();
    for s in &timeline.obj_track {
        *counts.entry(s.kind).or_default() += 1;
    }
    counts
}

/// Native-only debug entry point: parse a demo and print timeline stats.
/// Used by the tests/parse_native.rs harness for fast iteration off-browser.
#[cfg(not(target_arch = "wasm32"))]
pub fn debug_parse_demo(data: &[u8]) {
    let mut parser = demo::DemoParser::new(data);
    let parsed = parser.parse().expect("demo parse failed");
    let timeline = demo::build_timeline(&parsed, 0.05, data);
    println!(
        "RESULT: map={} duration={:.1}s entries={} events={} players={} hud_updates={}",
        parsed.header.map_name,
        timeline.duration,
        timeline.entries.len(),
        timeline.events.len(),
        parsed.players.len(),
        timeline.hud_track.len(),
    );
    let mut event_counts: std::collections::BTreeMap<String, usize> = Default::default();
    for event in &timeline.events {
        *event_counts
            .entry(format!("{:?}", event.event_type))
            .or_default() += 1;
    }
    println!("  event counts: {:?}", event_counts);
    if !timeline.entries.is_empty() {
        let first = &timeline.entries[0];
        let last = timeline.entries.last().unwrap();
        println!(
            "  first entry t={:.1} ({} players), last t={:.1} ({} players)",
            first.time,
            first.players.len(),
            last.time,
            last.players.len()
        );
        // largest gap between consecutive entries
        let mut max_gap = 0.0f32;
        let mut gap_at = 0.0f32;
        for w in timeline.entries.windows(2) {
            let gap = w[1].time - w[0].time;
            if gap > max_gap {
                max_gap = gap;
                gap_at = w[0].time;
            }
        }
        println!("  largest gap {:.1}s at t={:.1}", max_gap, gap_at);
        for t in [60.0f32, 300.0, 600.0, 900.0, 1200.0] {
            if let Some(e) = timeline.entries.iter().find(|e| e.time >= t) {
                let names: Vec<&str> = e.players.iter().take(3).map(|p| p.name.as_str()).collect();
                let p = &e.players[0];
                println!(
                    "  t={:.0}: {} players, p0 {} at ({:.0}, {:.0}, {:.0})",
                    e.time,
                    e.players.len(),
                    names.join(","),
                    p.origin.x,
                    p.origin.y,
                    p.origin.z
                );
            }
        }
    }
}

/// Parse a demo file and return the timeline for playback
#[wasm_bindgen]
pub fn parse_demo(data: &[u8]) -> Result<JsValue, JsValue> {
    let mut parser = demo::DemoParser::new(data);
    let parsed = parser.parse().map_err(|e| JsValue::from_str(&e))?;
    let timeline = demo::build_timeline(&parsed, 0.05, data);

    let players = if timeline.wire_players.is_empty() {
        parsed.players
    } else {
        timeline.wire_players.clone()
    };
    let result = DemoResult {
        map_name: parsed.header.map_name,
        duration: timeline.duration,
        timeline,
        players,
    };

    serde_wasm_bindgen::to_value(&result).map_err(|e| JsValue::from_str(&e.to_string()))
}

/// Like `parse_demo`, but reports progress (0.0..=1.0) through the given JS
/// callback and returns the result as a JSON string (serde_wasm_bindgen's
/// JsValue conversion takes ~50s for a full timeline; serde_json + JSON.parse
/// on the JS side is orders of magnitude faster). Intended to be called from
/// a Web Worker so the UI can render while parsing.
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen]
pub fn parse_demo_with_progress(
    data: &[u8],
    progress: &js_sys::Function,
) -> Result<String, JsValue> {
    let report = |f: f32| {
        let _ = progress.call1(&JsValue::NULL, &JsValue::from_f64(f as f64));
    };

    report(0.02);
    let mut parser = demo::DemoParser::new(data);
    let parsed = parser.parse().map_err(|e| JsValue::from_str(&e))?;
    report(0.08);

    let timeline = demo::build_timeline_with_progress(
        &parsed,
        0.05,
        data,
        Some(&|f: f32| report(0.08 + f * 0.77)),
    );
    report(0.85); // remainder: JSON serialization + parse on the JS side

    let players = if timeline.wire_players.is_empty() {
        parsed.players
    } else {
        timeline.wire_players.clone()
    };
    let result = DemoResult {
        map_name: parsed.header.map_name,
        duration: timeline.duration,
        timeline,
        players,
    };

    let json = serde_json::to_string(&result).map_err(|e| JsValue::from_str(&e.to_string()))?;
    report(0.92);
    Ok(json)
}

/// Structure-of-arrays timeline: fixed slot per player, flat arrays.
/// positions/angles are [entry][slot][xyz]; presence marks slot validity.
pub struct SoaTimeline {
    pub slot_names: Vec<String>,
    pub times: Vec<f32>,
    pub positions: Vec<f32>,
    pub angles: Vec<f32>,
    pub presence: Vec<u8>,
    pub pov_times: Vec<f32>,
    pub pov_data: Vec<f32>, // 6 per sample: origin xyz + angles xyz
    pub pov_weapon_bits: Vec<i32>,
    pub obj_times: Vec<f32>,
    pub obj_ents: Vec<u16>,
    pub obj_kinds: Vec<u8>,
    pub obj_positions: Vec<f32>, // 3 per sample
    pub gaits: Vec<u8>,          // [entry][slot]
    pub sequences: Vec<u8>,      // [entry][slot]
    pub frames: Vec<u8>,         // [entry][slot]
    pub effects: Vec<u32>,       // [entry][slot]
    pub ducking: Vec<u8>,        // [entry][slot]
    pub velocities: Vec<f32>,    // [entry][slot][xyz]
    pub weapons: Vec<u16>,       // [entry][slot] model index
    pub healths: Vec<i16>,       // [entry][slot], -1 when unavailable
    pub shot_times: Vec<f32>,
    pub shot_slots: Vec<u8>,
    pub hud_times: Vec<f32>,
    pub hud_kinds: Vec<u8>,
    pub hud_a: Vec<i32>,
    pub hud_b: Vec<i32>,
    pub observer_times: Vec<f32>,
    pub observer_targets: Vec<u16>,
    pub observer_modes: Vec<u8>,
    pub weapon_anim_times: Vec<f32>,
    pub weapon_anim_sequences: Vec<u8>,
    pub weapon_anim_bodies: Vec<u8>,
}

pub fn timeline_to_soa(timeline: &Timeline, roster: &[PlayerInfo]) -> SoaTimeline {
    let mut slot_names: Vec<String> = roster.iter().map(|p| p.name.clone()).collect();
    let mut slot_of: std::collections::HashMap<String, usize> = slot_names
        .iter()
        .enumerate()
        .map(|(i, n)| (n.clone(), i))
        .collect();

    // First pass: extend slots with any names outside the roster
    for entry in &timeline.entries {
        for p in &entry.players {
            if !slot_of.contains_key(&p.name) && slot_names.len() < 64 {
                slot_of.insert(p.name.clone(), slot_names.len());
                slot_names.push(p.name.clone());
            }
        }
    }

    let n_slots = slot_names.len().max(1);
    let n = timeline.entries.len();
    let mut times = Vec::with_capacity(n);
    let mut positions = vec![0f32; n * n_slots * 3];
    let mut angles = vec![0f32; n * n_slots * 3];
    let mut presence = vec![0u8; n * n_slots];
    let mut gaits = vec![0u8; n * n_slots];
    let mut sequences = vec![0u8; n * n_slots];
    let mut frames = vec![0u8; n * n_slots];
    let mut effects = vec![0u32; n * n_slots];
    let mut ducking = vec![0u8; n * n_slots];
    let mut velocities = vec![0f32; n * n_slots * 3];
    let mut weapons = vec![0u16; n * n_slots];
    let mut healths = vec![-1i16; n * n_slots];

    for (i, entry) in timeline.entries.iter().enumerate() {
        times.push(entry.time);
        for p in &entry.players {
            let Some(&slot) = slot_of.get(&p.name) else {
                continue;
            };
            let base = (i * n_slots + slot) * 3;
            positions[base] = p.origin.x;
            positions[base + 1] = p.origin.y;
            positions[base + 2] = p.origin.z;
            angles[base] = p.angles.x;
            angles[base + 1] = p.angles.y;
            angles[base + 2] = p.angles.z;
            presence[i * n_slots + slot] = 1;
            gaits[i * n_slots + slot] = p.gait;
            sequences[i * n_slots + slot] = p.sequence;
            frames[i * n_slots + slot] = p.frame;
            effects[i * n_slots + slot] = p.effects;
            ducking[i * n_slots + slot] = u8::from(p.ducking);
            velocities[base] = p.velocity.x;
            velocities[base + 1] = p.velocity.y;
            velocities[base + 2] = p.velocity.z;
            weapons[i * n_slots + slot] = p.weapon;
            healths[i * n_slots + slot] = p.health;
        }
    }

    let mut pov_times = Vec::with_capacity(timeline.pov_track.len());
    let mut pov_data = Vec::with_capacity(timeline.pov_track.len() * 6);
    let mut pov_weapon_bits = Vec::with_capacity(timeline.pov_track.len());
    for s in &timeline.pov_track {
        pov_times.push(s.time);
        pov_weapon_bits.push(s.weapon_bits);
        pov_data.extend_from_slice(&[
            s.origin.x, s.origin.y, s.origin.z, s.angles.x, s.angles.y, s.angles.z,
        ]);
    }

    let mut obj_times = Vec::with_capacity(timeline.obj_track.len());
    let mut obj_ents = Vec::with_capacity(timeline.obj_track.len());
    let mut obj_kinds = Vec::with_capacity(timeline.obj_track.len());
    let mut obj_positions = Vec::with_capacity(timeline.obj_track.len() * 3);
    for s in &timeline.obj_track {
        obj_times.push(s.time);
        obj_ents.push(s.ent);
        obj_kinds.push(s.kind);
        obj_positions.extend_from_slice(&[s.origin.x, s.origin.y, s.origin.z]);
    }

    let shot_times: Vec<f32> = timeline.shot_track.iter().map(|(t, _)| *t).collect();
    let shot_slots: Vec<u8> = timeline.shot_track.iter().map(|(_, s)| *s).collect();
    let hud_times: Vec<f32> = timeline
        .hud_track
        .iter()
        .map(|update| update.time)
        .collect();
    let hud_kinds: Vec<u8> = timeline
        .hud_track
        .iter()
        .map(|update| update.kind)
        .collect();
    let hud_a: Vec<i32> = timeline.hud_track.iter().map(|update| update.a).collect();
    let hud_b: Vec<i32> = timeline.hud_track.iter().map(|update| update.b).collect();
    let observer_times: Vec<f32> = timeline
        .observer_track
        .iter()
        .map(|sample| sample.time)
        .collect();
    let observer_targets: Vec<u16> = timeline
        .observer_track
        .iter()
        .map(|sample| sample.target)
        .collect();
    let observer_modes: Vec<u8> = timeline
        .observer_track
        .iter()
        .map(|sample| sample.mode)
        .collect();
    let weapon_anim_times: Vec<f32> = timeline
        .weapon_anim_track
        .iter()
        .map(|sample| sample.time)
        .collect();
    let weapon_anim_sequences: Vec<u8> = timeline
        .weapon_anim_track
        .iter()
        .map(|sample| sample.sequence)
        .collect();
    let weapon_anim_bodies: Vec<u8> = timeline
        .weapon_anim_track
        .iter()
        .map(|sample| sample.body)
        .collect();

    SoaTimeline {
        slot_names,
        times,
        positions,
        angles,
        presence,
        pov_times,
        pov_data,
        pov_weapon_bits,
        obj_times,
        obj_ents,
        obj_kinds,
        obj_positions,
        gaits,
        sequences,
        frames,
        effects,
        ducking,
        velocities,
        weapons,
        healths,
        shot_times,
        shot_slots,
        hud_times,
        hud_kinds,
        hud_a,
        hud_b,
        observer_times,
        observer_targets,
        observer_modes,
        weapon_anim_times,
        weapon_anim_sequences,
        weapon_anim_bodies,
    }
}

/// SoA parse entry point: returns a JS object with typed arrays for the
/// timeline (zero-copy transferable from a worker) and a JSON string for the
/// small metadata (events, roster, map name).
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen]
pub fn parse_demo_soa(data: &[u8], progress: &js_sys::Function) -> Result<JsValue, JsValue> {
    let report = |f: f32| {
        let _ = progress.call1(&JsValue::NULL, &JsValue::from_f64(f as f64));
    };

    report(0.02);
    let mut parser = demo::DemoParser::new(data);
    let parsed = parser.parse().map_err(|e| JsValue::from_str(&e))?;
    report(0.08);

    let timeline = demo::build_timeline_with_progress(
        &parsed,
        0.05,
        data,
        Some(&|f: f32| report(0.08 + f * 0.77)),
    );
    report(0.85);

    let players = if timeline.wire_players.is_empty() {
        parsed.players.clone()
    } else {
        timeline.wire_players.clone()
    };
    let soa = timeline_to_soa(&timeline, &players);

    #[derive(serde::Serialize)]
    struct Meta<'a> {
        map_name: &'a str,
        duration: f32,
        players: &'a [PlayerInfo],
        events: &'a [GameEvent],
        slot_names: &'a [String],
        model_names: &'a [(u16, String)],
        hud_weapons: &'a [HudWeaponDef],
        sounds: &'a [DemoSound],
        network_sounds: &'a [NetworkSound],
        temp_effects: &'a [TempEffect],
        player_stats: &'a [PlayerStatsUpdate],
    }
    let meta = serde_json::to_string(&Meta {
        map_name: &parsed.header.map_name,
        duration: timeline.duration,
        players: &players,
        events: &timeline.events,
        slot_names: &soa.slot_names,
        model_names: &timeline.model_names,
        hud_weapons: &timeline.hud_weapons,
        sounds: &timeline.sound_track,
        network_sounds: &timeline.network_sound_track,
        temp_effects: &timeline.temp_effect_track,
        player_stats: &timeline.player_stats_track,
    })
    .map_err(|e| JsValue::from_str(&e.to_string()))?;
    report(0.92);

    let obj = js_sys::Object::new();
    let set = |k: &str, v: JsValue| js_sys::Reflect::set(&obj, &k.into(), &v).unwrap();
    set("meta", JsValue::from_str(&meta));
    set("times", js_sys::Float32Array::from(&soa.times[..]).into());
    set(
        "positions",
        js_sys::Float32Array::from(&soa.positions[..]).into(),
    );
    set("angles", js_sys::Float32Array::from(&soa.angles[..]).into());
    set(
        "presence",
        js_sys::Uint8Array::from(&soa.presence[..]).into(),
    );
    set(
        "povTimes",
        js_sys::Float32Array::from(&soa.pov_times[..]).into(),
    );
    set(
        "povData",
        js_sys::Float32Array::from(&soa.pov_data[..]).into(),
    );
    set(
        "povWeaponBits",
        js_sys::Int32Array::from(&soa.pov_weapon_bits[..]).into(),
    );
    set(
        "objTimes",
        js_sys::Float32Array::from(&soa.obj_times[..]).into(),
    );
    set(
        "objEnts",
        js_sys::Uint16Array::from(&soa.obj_ents[..]).into(),
    );
    set(
        "objKinds",
        js_sys::Uint8Array::from(&soa.obj_kinds[..]).into(),
    );
    set(
        "objPositions",
        js_sys::Float32Array::from(&soa.obj_positions[..]).into(),
    );
    set("gaits", js_sys::Uint8Array::from(&soa.gaits[..]).into());
    set(
        "sequences",
        js_sys::Uint8Array::from(&soa.sequences[..]).into(),
    );
    set("frames", js_sys::Uint8Array::from(&soa.frames[..]).into());
    set(
        "effects",
        js_sys::Uint32Array::from(&soa.effects[..]).into(),
    );
    set("ducking", js_sys::Uint8Array::from(&soa.ducking[..]).into());
    set(
        "velocities",
        js_sys::Float32Array::from(&soa.velocities[..]).into(),
    );
    set(
        "weapons",
        js_sys::Uint16Array::from(&soa.weapons[..]).into(),
    );
    set("healths", js_sys::Int16Array::from(&soa.healths[..]).into());
    set(
        "shotTimes",
        js_sys::Float32Array::from(&soa.shot_times[..]).into(),
    );
    set(
        "shotSlots",
        js_sys::Uint8Array::from(&soa.shot_slots[..]).into(),
    );
    set(
        "hudTimes",
        js_sys::Float32Array::from(&soa.hud_times[..]).into(),
    );
    set(
        "hudKinds",
        js_sys::Uint8Array::from(&soa.hud_kinds[..]).into(),
    );
    set("hudA", js_sys::Int32Array::from(&soa.hud_a[..]).into());
    set("hudB", js_sys::Int32Array::from(&soa.hud_b[..]).into());
    set(
        "observerTimes",
        js_sys::Float32Array::from(&soa.observer_times[..]).into(),
    );
    set(
        "observerTargets",
        js_sys::Uint16Array::from(&soa.observer_targets[..]).into(),
    );
    set(
        "observerModes",
        js_sys::Uint8Array::from(&soa.observer_modes[..]).into(),
    );
    set(
        "weaponAnimTimes",
        js_sys::Float32Array::from(&soa.weapon_anim_times[..]).into(),
    );
    set(
        "weaponAnimSequences",
        js_sys::Uint8Array::from(&soa.weapon_anim_sequences[..]).into(),
    );
    set(
        "weaponAnimBodies",
        js_sys::Uint8Array::from(&soa.weapon_anim_bodies[..]).into(),
    );
    report(1.0);
    Ok(obj.into())
}

#[derive(serde::Serialize)]
struct DemoResult {
    map_name: String,
    duration: f32,
    timeline: Timeline,
    players: Vec<PlayerInfo>,
}

/// Textured BSP parse: per-texture geometry groups + RGBA pixels.
/// `wads` is a JS array of Uint8Array WAD3 file contents.
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen]
pub fn parse_bsp_textured(data: &[u8], wads: js_sys::Array) -> Result<JsValue, JsValue> {
    let mut wad_map = std::collections::HashMap::new();
    for w in wads.iter() {
        let bytes = js_sys::Uint8Array::new(&w).to_vec();
        bsp::parse_wad(&bytes, &mut wad_map);
    }
    let mut parser = bsp::BspParser::new(data);
    let t = parser
        .parse_textured(&wad_map)
        .map_err(|e| JsValue::from_str(&e))?;

    #[derive(serde::Serialize)]
    struct GroupMeta<'a> {
        name: &'a str,
        width: u32,
        height: u32,
        vert_start: u32,
        vert_count: u32,
        pix_offset: i64,
    }
    #[derive(serde::Serialize)]
    struct Meta<'a> {
        groups: Vec<GroupMeta<'a>>,
        entities: &'a [BspEntity],
        bounds_min: &'a Vec3,
        bounds_max: &'a Vec3,
    }
    let meta = serde_json::to_string(&Meta {
        groups: t
            .groups
            .iter()
            .map(|g| GroupMeta {
                name: &g.name,
                width: g.width,
                height: g.height,
                vert_start: g.vert_start,
                vert_count: g.vert_count,
                pix_offset: g.pix_offset,
            })
            .collect(),
        entities: &t.entities,
        bounds_min: &t.bounds_min,
        bounds_max: &t.bounds_max,
    })
    .map_err(|e| JsValue::from_str(&e.to_string()))?;

    let obj = js_sys::Object::new();
    let set = |k: &str, v: JsValue| js_sys::Reflect::set(&obj, &k.into(), &v).unwrap();
    set("meta", JsValue::from_str(&meta));
    set(
        "positions",
        js_sys::Float32Array::from(&t.positions[..]).into(),
    );
    set("normals", js_sys::Float32Array::from(&t.normals[..]).into());
    set("colors", js_sys::Float32Array::from(&t.colors[..]).into());
    set("uvs", js_sys::Float32Array::from(&t.uvs[..]).into());
    set("pixels", js_sys::Uint8Array::from(&t.pixels[..]).into());
    Ok(obj.into())
}

/// Parse a GoldSrc studio model (.mdl): static-pose geometry + textures.
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen]
pub fn parse_mdl(data: &[u8]) -> Result<JsValue, JsValue> {
    let (m, anims) = mdl::parse_mdl_animated(data).map_err(|e| JsValue::from_str(&e))?;

    #[derive(serde::Serialize)]
    struct GroupMeta<'a> {
        name: &'a str,
        width: u32,
        height: u32,
        vert_start: u32,
        vert_count: u32,
        pix_offset: i64,
    }
    let meta = serde_json::to_string(
        &m.groups
            .iter()
            .map(|g| GroupMeta {
                name: &g.tex_name,
                width: g.width,
                height: g.height,
                vert_start: g.vert_start,
                vert_count: g.vert_count,
                pix_offset: g.pix_offset,
            })
            .collect::<Vec<_>>(),
    )
    .map_err(|e| JsValue::from_str(&e.to_string()))?;

    let obj = js_sys::Object::new();
    let set = |k: &str, v: JsValue| js_sys::Reflect::set(&obj, &k.into(), &v).unwrap();
    set("meta", JsValue::from_str(&meta));
    set(
        "positions",
        js_sys::Float32Array::from(&m.positions[..]).into(),
    );
    set("uvs", js_sys::Float32Array::from(&m.uvs[..]).into());
    set("pixels", js_sys::Uint8Array::from(&m.pixels[..]).into());

    #[derive(serde::Serialize)]
    struct AnimMeta<'a> {
        name: &'a str,
        fps: f32,
        frames: u32,
    }
    let anim_meta = serde_json::to_string(
        &anims
            .iter()
            .map(|a| AnimMeta {
                name: &a.name,
                fps: a.fps,
                frames: a.frames,
            })
            .collect::<Vec<_>>(),
    )
    .map_err(|e| JsValue::from_str(&e.to_string()))?;
    set("animMeta", JsValue::from_str(&anim_meta));
    set(
        "seqLabels",
        JsValue::from_str(&serde_json::to_string(&m.seq_labels).unwrap_or_default()),
    );
    let anim_arr = js_sys::Array::new();
    for a in &anims {
        anim_arr.push(&js_sys::Float32Array::from(&a.data[..]).into());
    }
    set("animData", anim_arr.into());
    Ok(obj.into())
}

/// Parse a p_ weapon model bone-merged onto a player model's skeleton.
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen]
pub fn parse_mdl_attached(player: &[u8], weapon: &[u8]) -> Result<JsValue, JsValue> {
    let (m, anims) = mdl::parse_mdl_attached(player, weapon).map_err(|e| JsValue::from_str(&e))?;
    mdl_result_to_js(&m, &anims)
}

#[cfg(target_arch = "wasm32")]
fn mdl_result_to_js(m: &mdl::ParsedMdl, anims: &[mdl::MdlAnim]) -> Result<JsValue, JsValue> {
    #[derive(serde::Serialize)]
    struct GroupMeta<'a> {
        name: &'a str,
        width: u32,
        height: u32,
        vert_start: u32,
        vert_count: u32,
        pix_offset: i64,
    }
    let meta = serde_json::to_string(
        &m.groups
            .iter()
            .map(|g| GroupMeta {
                name: &g.tex_name,
                width: g.width,
                height: g.height,
                vert_start: g.vert_start,
                vert_count: g.vert_count,
                pix_offset: g.pix_offset,
            })
            .collect::<Vec<_>>(),
    )
    .map_err(|e| JsValue::from_str(&e.to_string()))?;

    #[derive(serde::Serialize)]
    struct AnimMeta<'a> {
        name: &'a str,
        fps: f32,
        frames: u32,
    }
    let anim_meta = serde_json::to_string(
        &anims
            .iter()
            .map(|a| AnimMeta {
                name: &a.name,
                fps: a.fps,
                frames: a.frames,
            })
            .collect::<Vec<_>>(),
    )
    .map_err(|e| JsValue::from_str(&e.to_string()))?;

    let obj = js_sys::Object::new();
    let set = |k: &str, v: JsValue| js_sys::Reflect::set(&obj, &k.into(), &v).unwrap();
    set("meta", JsValue::from_str(&meta));
    set(
        "positions",
        js_sys::Float32Array::from(&m.positions[..]).into(),
    );
    set("uvs", js_sys::Float32Array::from(&m.uvs[..]).into());
    set("pixels", js_sys::Uint8Array::from(&m.pixels[..]).into());
    set("animMeta", JsValue::from_str(&anim_meta));
    set(
        "seqLabels",
        JsValue::from_str(&serde_json::to_string(&m.seq_labels).unwrap_or_default()),
    );
    let anim_arr = js_sys::Array::new();
    for a in anims {
        anim_arr.push(&js_sys::Float32Array::from(&a.data[..]).into());
    }
    set("animData", anim_arr.into());
    Ok(obj.into())
}

/// Parse a BSP file and return flattened geometry arrays for Three.js
#[wasm_bindgen]
pub fn parse_bsp(data: &[u8]) -> Result<JsValue, JsValue> {
    let mut parser = bsp::BspParser::new(data);
    let parsed = parser.parse().map_err(|e| JsValue::from_str(&e))?;
    serde_wasm_bindgen::to_value(&parsed).map_err(|e| JsValue::from_str(&e.to_string()))
}

/// Get interpolated player state at a given time
/// Uses binary search for O(log n) performance
#[wasm_bindgen]
pub fn get_state_at_time(timeline_js: JsValue, time: f32) -> Result<JsValue, JsValue> {
    let timeline: Timeline = serde_wasm_bindgen::from_value(timeline_js)
        .map_err(|e| JsValue::from_str(&e.to_string()))?;

    if timeline.entries.is_empty() {
        return serde_wasm_bindgen::to_value(&Vec::<PlayerState>::new())
            .map_err(|e| JsValue::from_str(&e.to_string()));
    }

    // Binary search
    let mut left = 0usize;
    let mut right = timeline.entries.len() - 1;

    while left < right {
        let mid = (left + right + 1) / 2;
        if timeline.entries[mid].time <= time {
            left = mid;
        } else {
            right = mid - 1;
        }
    }

    let prev = &timeline.entries[left];
    let next = timeline.entries.get(left + 1);

    // Interpolate if we have a next entry
    let players = if let Some(next) = next {
        if next.time > prev.time {
            let t = (time - prev.time) / (next.time - prev.time);
            prev.players
                .iter()
                .zip(next.players.iter())
                .map(|(p, n)| PlayerState {
                    origin: Vec3::new(
                        p.origin.x + (n.origin.x - p.origin.x) * t,
                        p.origin.y + (n.origin.y - p.origin.y) * t,
                        p.origin.z + (n.origin.z - p.origin.z) * t,
                    ),
                    angles: Vec3::new(
                        lerp_angle(p.angles.x, n.angles.x, t),
                        lerp_angle(p.angles.y, n.angles.y, t),
                        lerp_angle(p.angles.z, n.angles.z, t),
                    ),
                    velocity: p.velocity.clone(),
                    gait: p.gait,
                    sequence: p.sequence,
                    frame: p.frame,
                    effects: p.effects,
                    ducking: p.ducking,
                    weapon: p.weapon,
                    health: p.health,
                    name: p.name.clone(),
                })
                .collect::<Vec<_>>()
        } else {
            prev.players.clone()
        }
    } else {
        prev.players.clone()
    };

    serde_wasm_bindgen::to_value(&players).map_err(|e| JsValue::from_str(&e.to_string()))
}

fn lerp_angle(a: f32, b: f32, t: f32) -> f32 {
    let mut diff = b - a;
    while diff > 180.0 {
        diff -= 360.0;
    }
    while diff < -180.0 {
        diff += 360.0;
    }
    a + diff * t
}
