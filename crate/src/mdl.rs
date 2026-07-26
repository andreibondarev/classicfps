/// GoldSrc studio model (.mdl, version 10) parser — static reference pose.
/// Emits per-texture triangle groups with UVs and RGBA pixels, mirroring the
/// textured-BSP output so the renderer shares one material path.

fn i32_at(d: &[u8], o: usize) -> i32 {
    i32::from_le_bytes(d[o..o + 4].try_into().unwrap())
}
fn f32_at(d: &[u8], o: usize) -> f32 {
    f32::from_le_bytes(d[o..o + 4].try_into().unwrap())
}
fn i16_at(d: &[u8], o: usize) -> i16 {
    i16::from_le_bytes(d[o..o + 2].try_into().unwrap())
}

/// 3x4 affine transform (row-major rows of [r r r t])
type Mat34 = [[f32; 4]; 3];

fn mat_identity() -> Mat34 {
    [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
    ]
}

fn mat_mul(a: &Mat34, b: &Mat34) -> Mat34 {
    let mut out = [[0f32; 4]; 3];
    for i in 0..3 {
        for j in 0..4 {
            out[i][j] = a[i][0] * b[0][j]
                + a[i][1] * b[1][j]
                + a[i][2] * b[2][j]
                + if j == 3 { a[i][3] } else { 0.0 };
        }
    }
    out
}

fn mat_apply(m: &Mat34, v: [f32; 3]) -> [f32; 3] {
    [
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2] + m[0][3],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2] + m[1][3],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2] + m[2][3],
    ]
}

/// GoldSrc AngleQuaternion + QuaternionMatrix, with translation appended
fn bone_local_matrix(pos: [f32; 3], ang: [f32; 3]) -> Mat34 {
    let (sr, cr) = (ang[0] * 0.5).sin_cos();
    let (sp, cp) = (ang[1] * 0.5).sin_cos();
    let (sy, cy) = (ang[2] * 0.5).sin_cos();
    let qx = sr * cp * cy - cr * sp * sy;
    let qy = cr * sp * cy + sr * cp * sy;
    let qz = cr * cp * sy - sr * sp * cy;
    let qw = cr * cp * cy + sr * sp * sy;

    [
        [
            1.0 - 2.0 * qy * qy - 2.0 * qz * qz,
            2.0 * qx * qy - 2.0 * qw * qz,
            2.0 * qx * qz + 2.0 * qw * qy,
            pos[0],
        ],
        [
            2.0 * qx * qy + 2.0 * qw * qz,
            1.0 - 2.0 * qx * qx - 2.0 * qz * qz,
            2.0 * qy * qz - 2.0 * qw * qx,
            pos[1],
        ],
        [
            2.0 * qx * qz - 2.0 * qw * qy,
            2.0 * qy * qz + 2.0 * qw * qx,
            1.0 - 2.0 * qx * qx - 2.0 * qy * qy,
            pos[2],
        ],
    ]
}

pub struct MdlGroup {
    pub tex_name: String,
    pub width: u32,
    pub height: u32,
    pub pix_offset: i64,
    pub vert_start: u32,
    pub vert_count: u32,
}

pub struct ParsedMdl {
    pub groups: Vec<MdlGroup>,
    pub positions: Vec<f32>, // three.js coords, GoldSrc units * 0.01
    pub uvs: Vec<f32>,
    pub pixels: Vec<u8>,
    pub seq_labels: Vec<String>,
}

/// All sequence labels, in sequence order
pub fn sequence_labels(d: &[u8]) -> Vec<String> {
    let numseq = i32_at(d, 164) as usize;
    let seqindex = i32_at(d, 168) as usize;
    let mut out = Vec::new();
    for s in 0..numseq.min(256) {
        let o = seqindex + s * 176;
        if o + 176 > d.len() {
            break;
        }
        let raw = &d[o..o + 32];
        let end = raw.iter().position(|&b| b == 0).unwrap_or(32);
        out.push(String::from_utf8_lossy(&raw[..end]).to_string());
    }
    out
}

/// Bind-pose bone matrices from bone default values
fn bind_pose_matrices(d: &[u8], numbones: usize, boneindex: usize) -> Result<Vec<Mat34>, String> {
    let mut bone_mats: Vec<Mat34> = Vec::with_capacity(numbones);
    for b in 0..numbones {
        let o = boneindex + b * 112;
        if o + 112 > d.len() {
            return Err("bone table out of range".into());
        }
        let parent = i32_at(d, o + 32);
        let vals: Vec<f32> = (0..6).map(|i| f32_at(d, o + 64 + i * 4)).collect();
        let local = bone_local_matrix([vals[0], vals[1], vals[2]], [vals[3], vals[4], vals[5]]);
        let world = if parent >= 0 && (parent as usize) < bone_mats.len() {
            mat_mul(&bone_mats[parent as usize], &local)
        } else {
            local
        };
        bone_mats.push(world);
    }
    Ok(bone_mats)
}

/// Decode one RLE animvalue channel at `frame`; returns delta in anim units
fn anim_value(d: &[u8], base: usize, frame: usize) -> f32 {
    let mut p = base;
    let mut k = frame;
    loop {
        if p + 2 > d.len() {
            return 0.0;
        }
        let valid = d[p] as usize;
        let total = d[p + 1] as usize;
        if total == 0 {
            return 0.0;
        }
        if k < total {
            let idx = if k < valid { k + 1 } else { valid };
            let o = p + idx * 2;
            if o + 2 > d.len() {
                return 0.0;
            }
            return i16_at(d, o) as f32;
        }
        k -= total;
        p += (valid + 1) * 2;
    }
}

/// Bone matrices for `frame` and authored blend of `seq` (seqgroup 0 only).
fn anim_pose_matrices(
    d: &[u8],
    numbones: usize,
    boneindex: usize,
    seqindex: usize,
    seq: usize,
    frame: usize,
    blend: usize,
) -> Result<Vec<Mat34>, String> {
    let so = seqindex + seq * 176;
    if so + 176 > d.len() {
        return Err("seqdesc out of range".into());
    }
    let seqgroup = i32_at(d, so + 156);
    let animindex = i32_at(d, so + 124) as usize;
    let numblends = i32_at(d, so + 120).max(1) as usize;
    if seqgroup != 0 {
        return Err("external seqgroup".into());
    }
    if blend >= numblends {
        return Err(format!(
            "blend {blend} outside sequence blend count {numblends}"
        ));
    }

    let mut bone_mats: Vec<Mat34> = Vec::with_capacity(numbones);
    for b in 0..numbones {
        let bo = boneindex + b * 112;
        let parent = i32_at(d, bo + 32);
        let vals: Vec<f32> = (0..6).map(|i| f32_at(d, bo + 64 + i * 4)).collect();
        let scales: Vec<f32> = (0..6).map(|i| f32_at(d, bo + 88 + i * 4)).collect();

        // Each authored blend owns a complete numbones-sized mstudioanim_t
        // table. The previous importer always read the first table, which
        // locked nine-way player aim sequences to their -90 degree endpoint.
        let ao = animindex + (blend * numbones + b) * 12;
        let mut dof = [0f32; 6];
        for j in 0..6 {
            dof[j] = vals[j];
            if ao + 12 <= d.len() {
                let off =
                    u16::from_le_bytes(d[ao + j * 2..ao + j * 2 + 2].try_into().unwrap()) as usize;
                if off != 0 {
                    dof[j] += anim_value(d, ao + off, frame) * scales[j];
                }
            }
        }
        let local = bone_local_matrix([dof[0], dof[1], dof[2]], [dof[3], dof[4], dof[5]]);
        let world = if parent >= 0 && (parent as usize) < bone_mats.len() {
            mat_mul(&bone_mats[parent as usize], &local)
        } else {
            local
        };
        bone_mats.push(world);
    }
    Ok(bone_mats)
}

pub struct MdlAnim {
    pub name: String,
    pub source_label: String,
    pub sequence_index: u32,
    pub fps: f32,
    pub frames: u32,
    pub looping: bool,
    pub blends: u32,
    pub blend_type: [i32; 2],
    pub blend_start: [f32; 2],
    pub blend_end: [f32; 2],
    /// Concatenated blend-major, per-frame positions. Each pose keeps the same
    /// vertex order as ParsedMdl.positions.
    pub data: Vec<f32>,
}

#[derive(Clone, Debug)]
struct SequenceInfo {
    index: usize,
    label: String,
    fps: f32,
    frames: usize,
    looping: bool,
    blends: usize,
    blend_type: [i32; 2],
    blend_start: [f32; 2],
    blend_end: [f32; 2],
}

/// Find the first exact sequence label from a preference-ordered list.
///
/// Player models contain labels such as `run`, `crouchrun`, `ref_shoot_ak47`,
/// and `crouch_shoot_ak47`. Substring matching is unsafe here: asking for
/// `shoot` would select a crouched carbine pose, while asking for `die` would
/// select `crouch_die`.
fn find_sequence(d: &[u8], labels: &[&str]) -> Option<SequenceInfo> {
    let numseq = i32_at(d, 164) as usize;
    let seqindex = i32_at(d, 168) as usize;
    for wanted in labels {
        for s in 0..numseq.min(256) {
            let o = seqindex + s * 176;
            if o + 176 > d.len() {
                break;
            }
            let label = String::from_utf8_lossy(&d[o..o + 32])
                .trim_end_matches('\0')
                .to_lowercase();
            if label == *wanted {
                let fps = f32_at(d, o + 32);
                let numframes = i32_at(d, o + 56) as usize;
                if numframes > 0 {
                    return Some(SequenceInfo {
                        index: s,
                        label,
                        fps: if fps > 0.0 { fps } else { 15.0 },
                        frames: numframes,
                        looping: i32_at(d, o + 36) & 1 != 0,
                        blends: i32_at(d, o + 120).max(1) as usize,
                        blend_type: [i32_at(d, o + 128), i32_at(d, o + 132)],
                        blend_start: [f32_at(d, o + 136), f32_at(d, o + 140)],
                        blend_end: [f32_at(d, o + 144), f32_at(d, o + 148)],
                    });
                }
            }
        }
    }
    None
}

fn walk_geometry(
    d: &[u8],
    bone_mats: &[Mat34],
    tex_meta: &[(String, u32, u32, i64)],
    numbodyparts: usize,
    bodypartindex: usize,
    numskinref: usize,
    skinindex: usize,
) -> std::collections::BTreeMap<usize, (Vec<f32>, Vec<f32>)> {
    let skin_of = |skinref: usize| -> usize {
        let o = skinindex + skinref * 2;
        if o + 2 <= d.len() && skinref < numskinref {
            i16_at(d, o) as usize
        } else {
            0
        }
    };
    // Geometry, bucketed per texture
    let mut buckets: std::collections::BTreeMap<usize, (Vec<f32>, Vec<f32>)> = Default::default();
    for bp in 0..numbodyparts {
        let o = bodypartindex + bp * 76;
        let nummodels = i32_at(d, o + 64) as usize;
        let modelindex = i32_at(d, o + 72) as usize;
        // Body group 0: first model of each bodypart
        for m in 0..nummodels.min(1) {
            let mo = modelindex + m * 112;
            if mo + 112 > d.len() {
                continue;
            }
            let nummesh = i32_at(d, mo + 72) as usize;
            let meshindex = i32_at(d, mo + 76) as usize;
            let numverts = i32_at(d, mo + 80) as usize;
            let vertinfoindex = i32_at(d, mo + 84) as usize;
            let vertindex = i32_at(d, mo + 88) as usize;
            if vertindex + numverts * 12 > d.len() || vertinfoindex + numverts > d.len() {
                continue;
            }

            // Transform all vertices by their bone's bind matrix
            let mut verts: Vec<[f32; 3]> = Vec::with_capacity(numverts);
            for v in 0..numverts {
                let bone = d[vertinfoindex + v] as usize;
                let p = [
                    f32_at(d, vertindex + v * 12),
                    f32_at(d, vertindex + v * 12 + 4),
                    f32_at(d, vertindex + v * 12 + 8),
                ];
                let w = if bone < bone_mats.len() {
                    mat_apply(&bone_mats[bone], p)
                } else {
                    p
                };
                verts.push(w);
            }

            for mesh in 0..nummesh {
                let me = meshindex + mesh * 20;
                if me + 20 > d.len() {
                    continue;
                }
                let mut tri = i32_at(d, me + 4) as usize;
                let skinref = i32_at(d, me + 8) as usize;
                let tex = skin_of(skinref).min(tex_meta.len().saturating_sub(1));
                let (tw, th) = (tex_meta[tex].1.max(1) as f32, tex_meta[tex].2.max(1) as f32);
                let bucket = buckets.entry(tex).or_default();

                // Triangle commands: i16 count (neg = fan), then per-vertex
                // [vertindex, normindex, s, t] shorts.
                loop {
                    if tri + 2 > d.len() {
                        break;
                    }
                    let n = i16_at(d, tri);
                    tri += 2;
                    if n == 0 {
                        break;
                    }
                    let fan = n < 0;
                    let count = n.unsigned_abs() as usize;
                    if tri + count * 8 > d.len() {
                        break;
                    }
                    let mut chain: Vec<([f32; 3], f32, f32)> = Vec::with_capacity(count);
                    for k in 0..count {
                        let e = tri + k * 8;
                        let vi = i16_at(d, e) as usize;
                        let s = i16_at(d, e + 4) as f32;
                        let t = i16_at(d, e + 6) as f32;
                        let p = verts.get(vi).copied().unwrap_or([0.0; 3]);
                        chain.push((p, (s + 0.5) / tw, (t + 0.5) / th));
                    }
                    tri += count * 8;

                    let emit = |b: &mut (Vec<f32>, Vec<f32>), v: &([f32; 3], f32, f32)| {
                        // GoldSrc -> three.js: (x, z, -y), scaled to world units
                        b.0.extend_from_slice(&[v.0[0] * 0.01, v.0[2] * 0.01, -v.0[1] * 0.01]);
                        b.1.extend_from_slice(&[v.1, v.2]);
                    };
                    for k in 2..chain.len() {
                        if fan {
                            emit(bucket, &chain[0]);
                            emit(bucket, &chain[k - 1]);
                            emit(bucket, &chain[k]);
                        } else if k % 2 == 0 {
                            emit(bucket, &chain[k - 2]);
                            emit(bucket, &chain[k - 1]);
                            emit(bucket, &chain[k]);
                        } else {
                            emit(bucket, &chain[k - 1]);
                            emit(bucket, &chain[k - 2]);
                            emit(bucket, &chain[k]);
                        }
                    }
                }
            }
        }
    }

    buckets
}

pub fn parse_mdl(d: &[u8]) -> Result<ParsedMdl, String> {
    if d.len() < 244 || &d[0..4] != b"IDST" {
        return Err("not a studio model".into());
    }
    let version = i32_at(d, 4);
    if version != 10 {
        return Err(format!("unsupported mdl version {version}"));
    }

    let numbones = i32_at(d, 140) as usize;
    let boneindex = i32_at(d, 144) as usize;
    let numtextures = i32_at(d, 180) as usize;
    let textureindex = i32_at(d, 184) as usize;
    let numskinref = i32_at(d, 192) as usize;
    let skinindex = i32_at(d, 200) as usize;
    let numbodyparts = i32_at(d, 204) as usize;
    let bodypartindex = i32_at(d, 208) as usize;

    if numbones > 512 || numtextures > 256 || numbodyparts > 64 {
        return Err("implausible mdl header".into());
    }

    let bone_mats = bind_pose_matrices(d, numbones, boneindex)?;

    // Textures -> RGBA blocks
    let mut pixels: Vec<u8> = Vec::new();
    let mut tex_meta: Vec<(String, u32, u32, i64)> = Vec::new();
    for t in 0..numtextures {
        let o = textureindex + t * 80;
        if o + 80 > d.len() {
            return Err("texture table out of range".into());
        }
        let name = String::from_utf8_lossy(&d[o..o + 64])
            .trim_end_matches('\0')
            .to_string();
        let w = i32_at(d, o + 68) as usize;
        let h = i32_at(d, o + 72) as usize;
        let idx = i32_at(d, o + 76) as usize;
        if w == 0 || h == 0 || w > 1024 || h > 1024 || idx + w * h + 768 > d.len() {
            tex_meta.push((name, 0, 0, -1));
            continue;
        }
        let pal = &d[idx + w * h..idx + w * h + 768];
        let off = pixels.len() as i64;
        for &p in &d[idx..idx + w * h] {
            let i = p as usize * 3;
            pixels.extend_from_slice(&[pal[i], pal[i + 1], pal[i + 2], 255]);
        }
        tex_meta.push((name, w as u32, h as u32, off));
    }

    let buckets = walk_geometry(
        d,
        &bone_mats,
        &tex_meta,
        numbodyparts,
        bodypartindex,
        numskinref,
        skinindex,
    );

    let mut out = ParsedMdl {
        groups: Vec::new(),
        positions: Vec::new(),
        uvs: Vec::new(),
        pixels,
        seq_labels: sequence_labels(d),
    };
    for (tex, (pos, uv)) in buckets {
        let (name, w, h, off) = tex_meta[tex].clone();
        out.groups.push(MdlGroup {
            tex_name: name,
            width: w,
            height: h,
            pix_offset: off,
            vert_start: (out.positions.len() / 3) as u32,
            vert_count: (pos.len() / 3) as u32,
        });
        out.positions.extend_from_slice(&pos);
        out.uvs.extend_from_slice(&uv);
    }
    Ok(out)
}

/// Parse a model AND bake idle/run animation frames (vertex positions per
/// frame, same order as ParsedMdl.positions).
pub fn parse_mdl_animated(d: &[u8]) -> Result<(ParsedMdl, Vec<MdlAnim>), String> {
    let base = parse_mdl(d)?;

    let numbones = i32_at(d, 140) as usize;
    let boneindex = i32_at(d, 144) as usize;
    let numskinref = i32_at(d, 192) as usize;
    let skinindex = i32_at(d, 200) as usize;
    let numbodyparts = i32_at(d, 204) as usize;
    let bodypartindex = i32_at(d, 208) as usize;
    let numtextures = i32_at(d, 180) as usize;
    let textureindex = i32_at(d, 184) as usize;

    // tex_meta dims for UV normalization (pixels not needed again)
    let mut tex_meta: Vec<(String, u32, u32, i64)> = Vec::new();
    for t in 0..numtextures {
        let o = textureindex + t * 80;
        if o + 80 > d.len() {
            break;
        }
        let name = String::from_utf8_lossy(&d[o..o + 64])
            .trim_end_matches('\0')
            .to_string();
        tex_meta.push((name, i32_at(d, o + 68) as u32, i32_at(d, o + 72) as u32, -1));
    }

    let mut anims = Vec::new();
    let labels = sequence_labels(d);
    let is_view_model = labels.iter().any(|label| {
        let label = label.to_lowercase();
        label.contains("shoot") || label.contains("reload") || label == "draw"
    }) && !labels
        .iter()
        .any(|label| label.to_lowercase().contains("run"));

    // First-person v_ models use the numeric DEM_WEAPONANIM sequence index.
    // Preserve the complete sequence table in index order so recorded shoot,
    // reload, draw, and attack commands select the correct baked animation.
    if is_view_model {
        let seqindex = i32_at(d, 168) as usize;
        for (seq, label) in labels.iter().enumerate() {
            let o = seqindex + seq * 176;
            if o + 176 > d.len() {
                break;
            }
            let fps = f32_at(d, o + 32);
            let frames = i32_at(d, o + 56).max(1) as usize;
            let blends = i32_at(d, o + 120).max(1) as usize;
            let mut data = Vec::new();
            let mut ok = true;
            for blend in 0..blends {
                for frame in 0..frames {
                    match anim_pose_matrices(d, numbones, boneindex, seqindex, seq, frame, blend) {
                        Ok(mats) => {
                            let buckets = walk_geometry(
                                d,
                                &mats,
                                &tex_meta,
                                numbodyparts,
                                bodypartindex,
                                numskinref,
                                skinindex,
                            );
                            for (_, (positions, _)) in buckets {
                                data.extend_from_slice(&positions);
                            }
                        }
                        Err(_) => {
                            ok = false;
                            break;
                        }
                    }
                }
                if !ok {
                    break;
                }
            }
            if ok && !data.is_empty() {
                anims.push(MdlAnim {
                    name: label.to_lowercase(),
                    source_label: label.to_lowercase(),
                    sequence_index: seq as u32,
                    fps: if fps > 0.0 { fps } else { 15.0 },
                    frames: frames as u32,
                    looping: i32_at(d, o + 36) & 1 != 0,
                    blends: blends as u32,
                    blend_type: [i32_at(d, o + 128), i32_at(d, o + 132)],
                    blend_start: [f32_at(d, o + 136), f32_at(d, o + 140)],
                    blend_end: [f32_at(d, o + 144), f32_at(d, o + 148)],
                    data,
                });
            } else {
                // Keep indices aligned even if one malformed sequence cannot
                // be baked; an empty entry safely falls back in the renderer.
                anims.push(MdlAnim {
                    name: label.to_lowercase(),
                    source_label: label.to_lowercase(),
                    sequence_index: seq as u32,
                    fps: 15.0,
                    frames: 0,
                    looping: false,
                    blends: 1,
                    blend_type: [0, 0],
                    blend_start: [0.0, 0.0],
                    blend_end: [1.0, 0.0],
                    data: Vec::new(),
                });
            }
        }
        return Ok((base, anims));
    }

    for (name, labels) in [
        ("idle", &["idle1", "idle"][..]),
        ("run", &["run", "walk"][..]),
        ("crouchidle", &["crouch_idle", "crouchidle"][..]),
        ("crouchrun", &["crouchrun", "crouch_run"][..]),
        (
            "crouchshoot",
            &[
                "crouch_shoot_ak47",
                "crouch_shoot_rifle",
                "crouch_shoot_carbine",
            ][..],
        ),
        (
            "shoot",
            &["ref_shoot_ak47", "ref_shoot_rifle", "ref_shoot_carbine"][..],
        ),
        (
            "crouchreload",
            &[
                "crouch_reload_ak47",
                "crouch_reload_rifle",
                "crouch_reload_carbine",
            ][..],
        ),
        (
            "reload",
            &["ref_reload_ak47", "ref_reload_rifle", "ref_reload_carbine"][..],
        ),
        ("die", &["death1", "death2", "death3"][..]),
    ] {
        let Some(sequence) = find_sequence(d, labels) else {
            continue;
        };
        let mut data = Vec::new();
        let mut ok = true;
        for blend in 0..sequence.blends {
            for frame in 0..sequence.frames {
                match anim_pose_matrices(
                    d,
                    numbones,
                    boneindex,
                    i32_at(d, 168) as usize,
                    sequence.index,
                    frame,
                    blend,
                ) {
                    Ok(mats) => {
                        let buckets = walk_geometry(
                            d,
                            &mats,
                            &tex_meta,
                            numbodyparts,
                            bodypartindex,
                            numskinref,
                            skinindex,
                        );
                        for (_, (pos, _)) in buckets {
                            data.extend_from_slice(&pos);
                        }
                    }
                    Err(_) => {
                        ok = false;
                        break;
                    }
                }
            }
            if !ok {
                break;
            }
        }
        if ok && !data.is_empty() {
            anims.push(MdlAnim {
                name: name.to_string(),
                source_label: sequence.label,
                sequence_index: sequence.index as u32,
                fps: sequence.fps,
                frames: sequence.frames as u32,
                looping: sequence.looping,
                blends: sequence.blends as u32,
                blend_type: sequence.blend_type,
                blend_start: sequence.blend_start,
                blend_end: sequence.blend_end,
                data,
            });
        }
    }
    Ok((base, anims))
}

/// Bone names of a model, in bone order
fn bone_names(d: &[u8]) -> Vec<String> {
    let numbones = i32_at(d, 140) as usize;
    let boneindex = i32_at(d, 144) as usize;
    let mut names = Vec::with_capacity(numbones);
    for b in 0..numbones.min(512) {
        let o = boneindex + b * 112;
        if o + 32 > d.len() {
            break;
        }
        let raw = &d[o..o + 32];
        let end = raw.iter().position(|&b| b == 0).unwrap_or(32);
        names.push(String::from_utf8_lossy(&raw[..end]).to_string());
    }
    names
}

fn attached_weapon_family(d: &[u8]) -> &'static str {
    let internal_name = if d.len() >= 72 {
        String::from_utf8_lossy(&d[8..72])
            .trim_end_matches('\0')
            .to_lowercase()
    } else {
        String::new()
    };
    let weapon = internal_name
        .rsplit('/')
        .next()
        .unwrap_or(&internal_name)
        .trim_start_matches("p_")
        .trim_end_matches(".mdl");
    match weapon {
        "ak47" => "ak47",
        "aug" | "famas" | "galil" | "m4a1" | "sg552" => "carbine",
        "awp" | "g3sg1" | "scout" | "sg550" => "rifle",
        "deagle" | "fiveseven" | "glock18" | "p228" | "usp" => "onehanded",
        "elite" => "dualpistols",
        "mac10" | "mp5" | "p90" | "tmp" | "ump45" => "mp5",
        "m3" | "m3super90" | "xm1014" => "shotgun",
        "m249" => "m249",
        "flashbang" | "hegrenade" | "smokegrenade" => "grenade",
        "c4" => "c4",
        "knife" => "knife",
        _ => "rifle",
    }
}

/// Parse a p_ weapon model posed on a PLAYER's skeleton (GoldSrc bonemerge):
/// weapon bones are matched to player bones by name, and weapon vertices are
/// baked through the player's bind pose + idle/run animation frames.
pub fn parse_mdl_attached(
    player: &[u8],
    weapon: &[u8],
) -> Result<(ParsedMdl, Vec<MdlAnim>), String> {
    // Weapon static parse for textures/uvs/groups (bind pose placeholder)
    let base = parse_mdl(weapon)?;

    let p_names = bone_names(player);
    let w_names = bone_names(weapon);
    let map: Vec<Option<usize>> = w_names
        .iter()
        .map(|wn| p_names.iter().position(|pn| pn == wn))
        .collect();
    let w_numskinref = i32_at(weapon, 192) as usize;
    let w_skinindex = i32_at(weapon, 200) as usize;
    let w_numbodyparts = i32_at(weapon, 204) as usize;
    let w_bodypartindex = i32_at(weapon, 208) as usize;
    let w_numtextures = i32_at(weapon, 180) as usize;
    let w_textureindex = i32_at(weapon, 184) as usize;
    let mut w_texmeta: Vec<(String, u32, u32, i64)> = Vec::new();
    for t in 0..w_numtextures {
        let o = w_textureindex + t * 80;
        if o + 80 > weapon.len() {
            break;
        }
        let name = String::from_utf8_lossy(&weapon[o..o + 64])
            .trim_end_matches('\0')
            .to_string();
        w_texmeta.push((
            name,
            i32_at(weapon, o + 68) as u32,
            i32_at(weapon, o + 72) as u32,
            -1,
        ));
    }

    let p_numbones = i32_at(player, 140) as usize;
    let p_boneindex = i32_at(player, 144) as usize;

    // Merge: matched bones take the player's world matrix; unmatched bones
    // (weapon helper bones like 'flash'/'Line02' that hold the mesh) chain
    // their own local transform under their merged parent.
    let w_boneindex = i32_at(weapon, 144) as usize;
    let remap = |p_mats: &[Mat34]| -> Vec<Mat34> {
        let mut out: Vec<Mat34> = Vec::with_capacity(map.len());
        for (b, m) in map.iter().enumerate() {
            if let Some(pi) = m {
                if *pi < p_mats.len() {
                    out.push(p_mats[*pi]);
                    continue;
                }
            }
            let o = w_boneindex + b * 112;
            let parent = i32_at(weapon, o + 32);
            let vals: Vec<f32> = (0..6).map(|i| f32_at(weapon, o + 64 + i * 4)).collect();
            let local = bone_local_matrix([vals[0], vals[1], vals[2]], [vals[3], vals[4], vals[5]]);
            let world = if parent >= 0 && (parent as usize) < out.len() {
                mat_mul(&out[parent as usize], &local)
            } else {
                local
            };
            out.push(world);
        }
        out
    };

    // Static pose on the player's bind skeleton
    let bind = bind_pose_matrices(player, p_numbones, p_boneindex)?;
    let mut positions = Vec::new();
    for (_, (pos, _)) in walk_geometry(
        weapon,
        &remap(&bind),
        &w_texmeta,
        w_numbodyparts,
        w_bodypartindex,
        w_numskinref,
        w_skinindex,
    ) {
        positions.extend_from_slice(&pos);
    }

    // Use the same player activity family selected by each original weapon.
    // Reusing AK poses for pistols, SMGs, and grenades puts a correctly merged
    // p_ model in the wrong authored hand pose.
    let family = attached_weapon_family(weapon);
    let crouch_shoot = format!("crouch_shoot_{family}");
    let standing_shoot = format!("ref_shoot_{family}");
    let crouch_reload = format!("crouch_reload_{family}");
    let standing_reload = format!("ref_reload_{family}");
    let mut anims = Vec::new();
    let sequence_specs = [
        ("idle", vec!["idle1", "idle"]),
        ("run", vec!["run", "walk"]),
        ("crouchidle", vec!["crouch_idle", "crouchidle"]),
        ("crouchrun", vec!["crouchrun", "crouch_run"]),
        ("crouchshoot", vec![crouch_shoot.as_str()]),
        ("shoot", vec![standing_shoot.as_str()]),
        ("crouchreload", vec![crouch_reload.as_str()]),
        ("reload", vec![standing_reload.as_str()]),
        ("die", vec!["death1", "death2", "death3"]),
    ];
    for (name, labels) in sequence_specs {
        let Some(sequence) = find_sequence(player, &labels) else {
            continue;
        };
        let mut data = Vec::new();
        let mut ok = true;
        for blend in 0..sequence.blends {
            for frame in 0..sequence.frames {
                match anim_pose_matrices(
                    player,
                    p_numbones,
                    p_boneindex,
                    i32_at(player, 168) as usize,
                    sequence.index,
                    frame,
                    blend,
                ) {
                    Ok(mats) => {
                        for (_, (pos, _)) in walk_geometry(
                            weapon,
                            &remap(&mats),
                            &w_texmeta,
                            w_numbodyparts,
                            w_bodypartindex,
                            w_numskinref,
                            w_skinindex,
                        ) {
                            data.extend_from_slice(&pos);
                        }
                    }
                    Err(_) => {
                        ok = false;
                        break;
                    }
                }
            }
            if !ok {
                break;
            }
        }
        if ok && !data.is_empty() {
            anims.push(MdlAnim {
                name: name.to_string(),
                source_label: sequence.label,
                sequence_index: sequence.index as u32,
                fps: sequence.fps,
                frames: sequence.frames as u32,
                looping: sequence.looping,
                blends: sequence.blends as u32,
                blend_type: sequence.blend_type,
                blend_start: sequence.blend_start,
                blend_end: sequence.blend_end,
                data,
            });
        }
    }

    let out = ParsedMdl {
        groups: base.groups,
        positions,
        uvs: base.uvs,
        pixels: base.pixels,
        // Attached animation metadata indexes the player skeleton's sequence
        // table, not the p_ weapon's (usually empty) table.
        seq_labels: sequence_labels(player),
    };
    Ok((out, anims))
}

#[cfg(test)]
mod tests {
    use super::*;

    const TERROR_MODEL: &[u8] = include_bytes!("../../public/models/player/terror/terror.mdl");
    const AK47_PLAYER_MODEL: &[u8] = include_bytes!("../../public/models/weapons/p_ak47.mdl");
    const DEAGLE_PLAYER_MODEL: &[u8] = include_bytes!("../../public/models/weapons/p_deagle.mdl");

    #[test]
    fn player_pose_lookup_prefers_standing_ak_and_death_sequences() {
        let shoot = find_sequence(TERROR_MODEL, &["ref_shoot_ak47"]).expect("AK firing sequence");
        let death = find_sequence(TERROR_MODEL, &["death1"]).expect("standing death sequence");

        assert_eq!(sequence_labels(TERROR_MODEL)[shoot.index], "ref_shoot_ak47");
        assert_eq!(sequence_labels(TERROR_MODEL)[death.index], "death1");
        assert_eq!(shoot.frames, 6);
        assert_eq!(shoot.blends, 9);
        assert_eq!(shoot.blend_type[0], 8);
        assert_eq!(shoot.blend_start[0], -90.0);
        assert_eq!(shoot.blend_end[0], 90.0);
        assert_eq!(death.frames, 36);
        assert!(!death.looping);
    }

    #[test]
    fn exported_player_sequences_preserve_source_frames_and_blends() {
        let (model, animations) = parse_mdl_animated(TERROR_MODEL).expect("animated player model");
        for (name, source, frames, blends) in [
            ("idle", "idle1", 61, 1),
            ("run", "run", 37, 1),
            ("crouchidle", "crouch_idle", 31, 1),
            ("crouchrun", "crouchrun", 31, 1),
            ("crouchshoot", "crouch_shoot_ak47", 5, 9),
            ("shoot", "ref_shoot_ak47", 6, 9),
            ("crouchreload", "crouch_reload_ak47", 91, 1),
            ("reload", "ref_reload_ak47", 91, 1),
            ("die", "death1", 36, 1),
        ] {
            let animation = animations
                .iter()
                .find(|animation| animation.name == name)
                .unwrap_or_else(|| panic!("missing {name} animation"));
            assert_eq!(animation.source_label, source);
            assert_eq!(animation.frames, frames);
            assert_eq!(animation.blends, blends);
            assert_eq!(
                animation.data.len(),
                model.positions.len() * frames as usize * blends as usize
            );
        }

        for name in ["shoot", "die"] {
            let animation = animations
                .iter()
                .find(|animation| animation.name == name)
                .unwrap_or_else(|| panic!("missing {name} animation"));
            let first_frame = &animation.data[..model.positions.len()];
            let minimum_y = first_frame
                .chunks_exact(3)
                .map(|position| position[1])
                .fold(f32::INFINITY, f32::min);
            assert!(
                minimum_y < -0.3,
                "{name} selected a crouched pose with minimum y {minimum_y}"
            );
        }

        let shoot = animations
            .iter()
            .find(|animation| animation.name == "shoot")
            .expect("shoot animation");
        let pose_floats = model.positions.len() * shoot.frames as usize;
        let endpoint = &shoot.data[..model.positions.len()];
        let center_start = pose_floats * 4;
        let center = &shoot.data[center_start..center_start + model.positions.len()];
        assert!(
            endpoint
                .iter()
                .zip(center)
                .any(|(left, right)| (left - right).abs() >= 0.0001),
            "authored level-aim blend must not collapse to the -90 degree endpoint"
        );

        let death = animations
            .iter()
            .find(|animation| animation.name == "die")
            .expect("death animation");
        let final_start = (death.frames as usize - 1) * model.positions.len();
        assert_ne!(
            &death.data[..model.positions.len()],
            &death.data[final_start..final_start + model.positions.len()],
            "death must preserve its authored final pose"
        );
    }

    #[test]
    fn attached_weapon_preserves_player_action_sequences() {
        let (model, animations) =
            parse_mdl_attached(TERROR_MODEL, AK47_PLAYER_MODEL).expect("attached AK-47");
        for (name, frames, blends) in [
            ("shoot", 6, 9),
            ("crouchshoot", 5, 9),
            ("reload", 91, 1),
            ("crouchreload", 91, 1),
            ("die", 36, 1),
        ] {
            let animation = animations
                .iter()
                .find(|animation| animation.name == name)
                .unwrap_or_else(|| panic!("missing attached {name} animation"));
            assert_eq!(animation.frames, frames);
            assert_eq!(animation.blends, blends);
            assert_eq!(
                animation.data.len(),
                model.positions.len() * frames as usize * blends as usize
            );
        }
    }

    #[test]
    fn attached_weapon_uses_its_authored_activity_family() {
        assert_eq!(attached_weapon_family(AK47_PLAYER_MODEL), "ak47");
        assert_eq!(attached_weapon_family(DEAGLE_PLAYER_MODEL), "onehanded");
        let (_, animations) =
            parse_mdl_attached(TERROR_MODEL, DEAGLE_PLAYER_MODEL).expect("attached Deagle");
        assert_eq!(
            animations
                .iter()
                .find(|animation| animation.name == "shoot")
                .expect("Deagle shoot")
                .source_label,
            "ref_shoot_onehanded"
        );
        assert_eq!(
            animations
                .iter()
                .find(|animation| animation.name == "reload")
                .expect("Deagle reload")
                .source_label,
            "ref_reload_onehanded"
        );
    }
}
