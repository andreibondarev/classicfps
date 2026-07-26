// Native harness for iterating on demo parsing without the WASM/browser loop.
// Run with: cargo test --release --test parse_native -- --nocapture

use cs16_demo_parser::debug_parse_demo;

fn collect_models(directory: &std::path::Path, models: &mut Vec<std::path::PathBuf>) {
    for entry in std::fs::read_dir(directory).expect("model directory") {
        let path = entry.expect("model entry").path();
        if path.is_dir() {
            collect_models(&path, models);
        } else if path.extension().is_some_and(|extension| extension == "mdl") {
            models.push(path);
        }
    }
}

#[test]
fn complete_runtime_model_bundle_parses() {
    let root = std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../public/models"));
    let mut models = Vec::new();
    collect_models(&root.join("player"), &mut models);
    collect_models(&root.join("weapons"), &mut models);
    assert!(
        models.len() >= 123,
        "runtime model bundle is incomplete: found {}",
        models.len()
    );

    let mut parseable = 0;
    let mut auxiliary = Vec::new();
    for path in models {
        let data = std::fs::read(&path).expect("model file");
        if cs16_demo_parser::debug_mdl_valid(&data) {
            parseable += 1;
        } else {
            auxiliary.push(path);
        }
    }
    assert!(
        parseable >= 123,
        "runtime model bundle has only {parseable} parseable models; auxiliary files: {auxiliary:?}"
    );
}

#[test]
fn parse_pov_demo() {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../demos/col-3d-inf-finals-ct.dem"
    );
    let data = std::fs::read(path).expect("demo file");
    debug_parse_demo(&data);
}

#[test]
fn parse_hltv_demo() {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../demos/territory.ru--vs-Virtus.pro-hltv-0411281802-de_inferno.dem"
    );
    let data = std::fs::read(path).expect("demo file");
    debug_parse_demo(&data);
}

#[test]
fn parse_wcg07_demo() {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../demos/R1_TNTvsEMV.NX-0709081213-de_dust2.dem"
    );
    let data = std::fs::read(path).expect("demo file");
    cs16_demo_parser::debug_parse_demo(&data);
}

#[test]
fn hltv_demo_entity_names() {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../demos/territory.ru--vs-Virtus.pro-hltv-0411281802-de_inferno.dem"
    );
    let data = std::fs::read(path).expect("demo file");
    let names = cs16_demo_parser::debug_distinct_entity_names(&data);
    println!("distinct entity names: {:#?}", names);
    assert!(
        names.iter().any(|n| n.contains("drzky")),
        "drzky should be mapped to an entity"
    );
    assert!(
        names.iter().any(|n| n.contains("DRON")),
        "DRON should be mapped to an entity"
    );
}

/// Corpus invariants: every demo in demos/ and demos/corpus must parse into a
/// sane timeline. This is the guardrail for parser/decoder changes.
#[test]
fn corpus_invariants() {
    let mut dirs = vec![std::path::PathBuf::from(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../demos"
    ))];
    dirs.push(dirs[0].join("corpus"));

    let mut checked = 0;
    for dir in dirs {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("dem") {
                continue;
            }
            let name = path.file_name().unwrap().to_string_lossy().to_string();
            // This legacy POV recording stores almost all useful state in a
            // framing variant exercised by the browser corpus verifier. The
            // native timeline-stat helper intentionally does not decode it.
            if name == "mamazVSc2[1].dem" {
                continue;
            }
            let data = std::fs::read(&path).expect("read demo");
            let (duration, n_entries, names, max_abs) =
                cs16_demo_parser::debug_timeline_stats(&data)
                    .unwrap_or_else(|e| panic!("{name}: parse failed: {e}"));

            assert!(
                duration > 60.0 && duration < 7200.0,
                "{name}: bad duration {duration}"
            );
            assert!(n_entries > 1000, "{name}: only {n_entries} entries");
            let real_names = names.iter().filter(|n| !n.starts_with("Player ")).count();
            assert!(
                real_names >= 6,
                "{name}: only {real_names} real names: {names:?}"
            );
            assert!(
                max_abs < 8192.0,
                "{name}: position out of bounds ({max_abs})"
            );
            println!("OK {name}: {duration:.0}s, {n_entries} entries, {real_names} named players");
            checked += 1;
        }
    }
    assert!(
        checked >= 9,
        "expected at least 9 corpus demos, found {checked}"
    );
}

/// Ad-hoc: parse the demo named by DEMO_PATH env var with full debug output
#[test]
fn parse_env_demo() {
    let Ok(path) = std::env::var("DEMO_PATH") else {
        return;
    };
    let data = std::fs::read(&path).expect("demo file");
    cs16_demo_parser::debug_parse_demo(&data);
}

#[test]
fn protocol46_exevsisterhood_has_real_players_without_garbage_hud_events() {
    let data = std::fs::read(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../demos/Exevsisterhood.dem"
    ))
    .expect("Exevsisterhood demo");
    let (duration, entries, names, max_abs, team_scores, round_times) =
        cs16_demo_parser::debug_timeline_diagnostics(&data).expect("timeline diagnostics");

    assert!((duration - 1754.8774).abs() < 0.1, "duration={duration}");
    assert!(entries > 20_000, "only {entries} player timeline entries");
    for expected in [
        "*sisterhood*<gandjubas>",
        "*sisterhood*<cyrus>",
        "exe^Hvorost",
        "exe^sNo0p",
    ] {
        assert!(
            names.iter().any(|name| name == expected),
            "missing {expected}; names={names:?}"
        );
    }
    assert!(max_abs < 8192.0, "position out of bounds: {max_abs}");
    assert_eq!(
        team_scores,
        vec![("CT".to_string(), 5), ("TERRORIST".to_string(), 2)]
    );
    assert!(
        round_times.is_empty(),
        "protocol-46 stream produced garbage RoundTime values: {round_times:?}"
    );
}

#[test]
fn exe_hltv_reconstructed_camera_targets_stay_inside_stock_map_height() {
    let cases = [
        (
            "/../demos/exe_vs_sisterhood-1.dem",
            332.93,
            "*sisterhood*<gandjubas>",
            -768.0..=128.0,
        ),
        (
            "/../demos/fs_vs_exe-1.dem",
            817.55,
            "exe^MaN@X` |~POSTNET",
            -1088.0..=128.0,
        ),
    ];

    for (relative, time, target, world_z) in cases {
        let path = format!("{}{}", env!("CARGO_MANIFEST_DIR"), relative);
        let data = std::fs::read(&path).unwrap_or_else(|error| panic!("{path}: {error}"));
        let (sample_time, origin, angles, _) =
            cs16_demo_parser::debug_player_pose_at(&data, time, target)
                .unwrap_or_else(|error| panic!("{path}: {error}"))
                .unwrap_or_else(|| panic!("{path}: missing target {target}"));

        assert!(
            (sample_time - time).abs() < 0.1,
            "{path}: nearest {target} sample is {sample_time}, requested {time}"
        );
        assert!(
            world_z.contains(&origin.z),
            "{path}: {target} camera origin {origin:?} is outside world Z {world_z:?}; \
             this indicates signed GoldSrc deltas were decoded as two's-complement"
        );
        assert!(
            [origin.x, origin.y, origin.z, angles.x, angles.y, angles.z]
                .into_iter()
                .all(f32::is_finite),
            "{path}: non-finite pose origin={origin:?} angles={angles:?}"
        );
    }
}

/// Objects (grenades/C4) should appear in the WCG demo's obj track
#[test]
fn object_track_present() {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../demos/R1_TNTvsEMV.NX-0709081213-de_dust2.dem"
    );
    let data = std::fs::read(path).expect("demo file");
    let counts = cs16_demo_parser::debug_obj_track_counts(&data);
    println!("obj kinds: {:?}", counts);
    let total: usize = counts.values().sum();
    assert!(total > 50, "expected object samples, got {total}");
}

#[test]
fn weapon_bonemerge() {
    let player = std::fs::read(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../public/models/player/sas/sas.mdl"
    ))
    .unwrap();
    let weapon = std::fs::read(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../public/models/weapons/p_m4a1.mdl"
    ))
    .unwrap();
    let (raw, merged, anim_center, n_anims) = cs16_demo_parser::debug_attach_bbox(&player, &weapon);
    println!(
        "raw {:?} merged {:?} animFrame0 {:?} anims {}",
        raw, merged, anim_center, n_anims
    );
    assert!(n_anims >= 2, "expected merged anims");
    // Bind poses coincide (same reference pose) — the anim frame must place
    // the gun at the animated hand, not at the model origin.
    let mag = (anim_center.0.powi(2) + anim_center.1.powi(2) + anim_center.2.powi(2)).sqrt();
    assert!(
        mag > 0.15,
        "anim frame gun should not sit at origin (|c|={mag})"
    );
}

#[test]
fn first_person_weapon_sequences_stay_index_aligned() {
    let model = std::fs::read(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../public/models/weapons/v_awp.mdl"
    ))
    .unwrap();
    let labels = cs16_demo_parser::debug_mdl_animation_labels(&model);
    assert_eq!(
        labels,
        vec!["idle1", "shoot1", "shoot2", "shoot3", "reload", "draw"],
    );
}

#[test]
fn shot_track_present() {
    let data = std::fs::read(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../demos/R1_TNTvsEMV.NX-0709081213-de_dust2.dem"
    ))
    .unwrap();
    let n = cs16_demo_parser::debug_shot_count(&data);
    println!("shots: {n}");
    assert!(n > 300, "expected gunfire events, got {n}");
}

#[test]
fn pov_rounds_are_reconstructed_without_duplicate_winners() {
    let data = std::fs::read(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../demos/col-3d-inf-finals-ct.dem"
    ))
    .unwrap();
    let counts = cs16_demo_parser::debug_event_counts(&data);
    let starts = *counts.get("RoundStart").unwrap_or(&0);
    let ends = *counts.get("RoundEnd").unwrap_or(&0);
    println!("normalized POV rounds: starts={starts}, ends={ends}");
    assert!(
        ends >= 10 && ends <= 20,
        "implausible round results: {ends}"
    );
    assert!(
        starts >= ends.saturating_sub(1),
        "missing reconstructed starts: {starts}/{ends}"
    );
    assert!(starts <= ends + 1, "duplicate starts: {starts}/{ends}");
}
