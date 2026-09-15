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
    /// One texture per authored skin family, in studiohdr_t skin order.
    pub skin_textures: Vec<MdlTexture>,
    pub vert_start: u32,
    pub vert_count: u32,
}

#[derive(Clone)]
pub struct MdlTexture {
    pub tex_name: String,
    pub width: u32,
    pub height: u32,
    pub pix_offset: i64,
}

pub struct ParsedMdl {
    pub groups: Vec<MdlGroup>,
    pub positions: Vec<f32>, // three.js coords, GoldSrc units * 0.01
    pub uvs: Vec<f32>,
    pub pixels: Vec<u8>,
    pub seq_labels: Vec<String>,
    /// One bit per emitted vertex: pelvis/leg ownership from the source bones.
    pub lower_body_mask: Vec<u8>,
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

/// Names of the external sequence-group files in GoldSrc group-index order.
///
/// Group zero is stored in the main IDST model and is intentionally omitted,
/// so the first returned name corresponds to sequence group one.
pub fn external_sequence_group_names(d: &[u8]) -> Result<Vec<String>, String> {
    if d.len() < 244 || &d[0..4] != b"IDST" {
        return Err("not a studio model".into());
    }
    if i32_at(d, 4) != 10 {
        return Err(format!("unsupported mdl version {}", i32_at(d, 4)));
    }
    let num_groups = i32_at(d, 172);
    let group_index = i32_at(d, 176);
    if num_groups < 1 || num_groups > 64 || group_index < 0 {
        return Err("implausible sequence group table".into());
    }
    let num_groups = num_groups as usize;
    let group_index = group_index as usize;
    let table_size = num_groups
        .checked_mul(104)
        .ok_or_else(|| "sequence group table overflow".to_string())?;
    if group_index
        .checked_add(table_size)
        .filter(|end| *end <= d.len())
        .is_none()
    {
        return Err("sequence group table out of range".into());
    }

    let mut names = Vec::with_capacity(num_groups.saturating_sub(1));
    for group in 1..num_groups {
        // mstudioseqgroup_t: label[32], name[64], cache pointer, data.
        let offset = group_index + group * 104 + 32;
        let raw = &d[offset..offset + 64];
        let end = raw.iter().position(|&byte| byte == 0).unwrap_or(raw.len());
        let name = String::from_utf8_lossy(&raw[..end]).to_string();
        if name.is_empty() {
            return Err(format!("sequence group {group} has no filename"));
        }
        names.push(name);
    }
    Ok(names)
}

fn validate_external_sequence_group(d: &[u8], group: usize) -> Result<(), String> {
    if d.len() < 76 || &d[0..4] != b"IDSQ" {
        return Err(format!("sequence group {group} is not an IDSQ model"));
    }
    if i32_at(d, 4) != 10 {
        return Err(format!(
            "sequence group {group} has unsupported version {}",
            i32_at(d, 4)
        ));
    }
    let authored_length = i32_at(d, 72);
    if authored_length < 76 || authored_length as usize > d.len() {
        return Err(format!(
            "sequence group {group} has invalid authored length {authored_length}"
        ));
    }
    Ok(())
}

/// Bone matrices for `frame` and authored blend of `seq`.
///
/// `external_groups[0]` is GoldSrc sequence group one, matching the order
/// returned by [`external_sequence_group_names`]. Group zero continues to
/// read animation data from the main IDST model.
/// Resolve a sequence's animation data source, mstudioanim_t table offset,
/// and blend count. `external_groups[0]` is GoldSrc sequence group one.
fn sequence_anim_source<'a>(
    d: &'a [u8],
    external_groups: &[&'a [u8]],
    seqindex: usize,
    seq: usize,
) -> Result<(&'a [u8], usize, usize), String> {
    let so = seqindex + seq * 176;
    if so + 176 > d.len() {
        return Err("seqdesc out of range".into());
    }
    let seqgroup = i32_at(d, so + 156);
    let animindex = i32_at(d, so + 124) as usize;
    let numblends = i32_at(d, so + 120).max(1) as usize;
    let anim_data = if seqgroup == 0 {
        d
    } else if seqgroup > 0 {
        let group_index = seqgroup as usize;
        let group = external_groups
            .get(group_index - 1)
            .ok_or_else(|| format!("external sequence group {group_index} is unavailable"))?;
        validate_external_sequence_group(group, group_index)?;
        *group
    } else {
        return Err(format!("invalid sequence group {seqgroup}"));
    };
    Ok((anim_data, animindex, numblends))
}

/// One bone's authored local transform for a sequence sample.
///
/// Each authored blend owns a complete numbones-sized mstudioanim_t table.
fn bone_local_pose_matrix(
    d: &[u8],
    anim_data: &[u8],
    boneindex: usize,
    numbones: usize,
    b: usize,
    animindex: usize,
    blend: usize,
    frame: usize,
) -> Mat34 {
    let bo = boneindex + b * 112;
    let vals: Vec<f32> = (0..6).map(|i| f32_at(d, bo + 64 + i * 4)).collect();
    let scales: Vec<f32> = (0..6).map(|i| f32_at(d, bo + 88 + i * 4)).collect();
    let ao = animindex + (blend * numbones + b) * 12;
    let mut dof = [0f32; 6];
    for j in 0..6 {
        dof[j] = vals[j];
        if ao + 12 <= anim_data.len() {
            let off = u16::from_le_bytes(anim_data[ao + j * 2..ao + j * 2 + 2].try_into().unwrap())
                as usize;
            if off != 0 {
                dof[j] += anim_value(anim_data, ao + off, frame) * scales[j];
            }
        }
    }
    bone_local_matrix([dof[0], dof[1], dof[2]], [dof[3], dof[4], dof[5]])
}

fn anim_pose_matrices(
    d: &[u8],
    external_groups: &[&[u8]],
    numbones: usize,
    boneindex: usize,
    seqindex: usize,
    seq: usize,
    frame: usize,
    blend: usize,
) -> Result<Vec<Mat34>, String> {
    let (anim_data, animindex, numblends) = sequence_anim_source(d, external_groups, seqindex, seq)?;
    if blend >= numblends {
        return Err(format!(
            "blend {blend} outside sequence blend count {numblends}"
        ));
    }

    let mut bone_mats: Vec<Mat34> = Vec::with_capacity(numbones);
    for b in 0..numbones {
        let bo = boneindex + b * 112;
        let parent = i32_at(d, bo + 32);
        let local = bone_local_pose_matrix(
            d, anim_data, boneindex, numbones, b, animindex, blend, frame,
        );
        let world = if parent >= 0 && (parent as usize) < bone_mats.len() {
            mat_mul(&bone_mats[parent as usize], &local)
        } else {
            local
        };
        bone_mats.push(world);
    }
    Ok(bone_mats)
}

/// Index of the upper-body branch, not an array boundary: legs follow the arms
/// in the stock CS skeleton. StudioSetupBones resumes gait at pelvis children.
fn spine_bone_index(d: &[u8]) -> Option<usize> {
    bone_names(d).iter().position(|name| name == "Bip01 Spine")
}

fn gait_bone_mask(d: &[u8]) -> Option<Vec<bool>> {
    spine_bone_index(d)?;
    let names = bone_names(d);
    let boneindex = i32_at(d, 144) as usize;
    let mut gait = Vec::with_capacity(names.len());
    let mut copy_gait = true;
    for (b, name) in names.iter().enumerate() {
        let parent = i32_at(d, boneindex + b * 112 + 32);
        // Match StudioSetupBones' branch switches, including late helper bones.
        // Stopping once at Spine incorrectly freezes both subsequent leg chains.
        if name == "Bip01 Spine" {
            copy_gait = false;
        } else if parent >= 0 && names.get(parent as usize).is_some_and(|n| n == "Bip01 Pelvis") {
            copy_gait = true;
        }
        gait.push(copy_gait);
    }
    Some(gait)
}

/// GoldSrc third-person player pose: legs and pelvis follow the gait
/// sequence while the spine, arms, and head follow the aim/shoot sequence.
#[allow(clippy::too_many_arguments)]
fn composite_pose_matrices(
    d: &[u8],
    external_groups: &[&[u8]],
    numbones: usize,
    boneindex: usize,
    seqindex: usize,
    gait_seq: usize,
    gait_frame: usize,
    aim_seq: usize,
    aim_frame: usize,
    aim_blend: usize,
) -> Result<Vec<Mat34>, String> {
    let Some(gait_mask) = gait_bone_mask(d) else {
        return anim_pose_matrices(
            d,
            external_groups,
            numbones,
            boneindex,
            seqindex,
            aim_seq,
            aim_frame,
            aim_blend,
        );
    };
    let (gait_data, gait_animindex, _) =
        sequence_anim_source(d, external_groups, seqindex, gait_seq)?;
    let (aim_data, aim_animindex, aim_blends) =
        sequence_anim_source(d, external_groups, seqindex, aim_seq)?;
    if aim_blend >= aim_blends {
        return Err(format!(
            "blend {aim_blend} outside sequence blend count {aim_blends}"
        ));
    }
    let mut bone_mats: Vec<Mat34> = Vec::with_capacity(numbones);
    for b in 0..numbones {
        let bo = boneindex + b * 112;
        let parent = i32_at(d, bo + 32);
        let local = if gait_mask[b] {
            bone_local_pose_matrix(
                d,
                gait_data,
                boneindex,
                numbones,
                b,
                gait_animindex,
                0,
                gait_frame,
            )
        } else {
            bone_local_pose_matrix(
                d,
                aim_data,
                boneindex,
                numbones,
                b,
                aim_animindex,
                aim_blend,
                aim_frame,
            )
        };
        let world = if parent >= 0 && (parent as usize) < bone_mats.len() {
            mat_mul(&bone_mats[parent as usize], &local)
        } else {
            local
        };
        bone_mats.push(world);
    }
    Ok(bone_mats)
}

/// One baked output pose: either a raw authored sequence sample or the
/// gait-composited player pose.
enum PoseSample {
    Full {
        seq: usize,
        frame: usize,
        blend: usize,
    },
    Composite {
        gait_seq: usize,
        gait_frame: usize,
        aim_seq: usize,
        aim_frame: usize,
        aim_blend: usize,
    },
}

/// Baked animation plan entry shared between the player-body exporter and
/// the attached p_ weapon exporter so both walk the exact same matrices.
struct PosePlanEntry {
    name: &'static str,
    source_label: String,
    sequence_index: u32,
    fps: f32,
    frames: u32,
    looping: bool,
    blends: u32,
    blend_type: [i32; 2],
    blend_start: [f32; 2],
    blend_end: [f32; 2],
    /// Blend-major, then frame order — matching the export data layout.
    poses: Vec<PoseSample>,
}

/// Source-faithful third-person pose plan for one weapon activity family.
///
/// Locomotion states keep the gait sequence's timing with the family's
/// level (center-blend) aim pose layered on the upper body; shoot/reload
/// states keep the aim layer's authored timing and pitch blends over a
/// stationary gait frame. Returns None when the model has no aim layers
/// (hostages, misc models) so callers keep the plain full-sequence bake.
fn player_pose_plan(d: &[u8], family: &str) -> Option<Vec<PosePlanEntry>> {
    let ref_aim_label = format!("ref_aim_{family}");
    let crouch_aim_label = format!("crouch_aim_{family}");
    let ref_aim = find_sequence(d, &[ref_aim_label.as_str()])?;
    let crouch_aim = find_sequence(d, &[crouch_aim_label.as_str()]).unwrap_or(ref_aim.clone());
    spine_bone_index(d)?;

    let gait_idle = find_sequence(d, &["idle1", "idle"])?;
    let gait_run = find_sequence(d, &["run", "walk"])?;
    let gait_crouch_idle = find_sequence(d, &["crouch_idle", "crouchidle"])?;
    let gait_crouch_run = find_sequence(d, &["crouchrun", "crouch_run"])?;

    let mut plan = Vec::new();
    let center_blend = |aim: &SequenceInfo| (aim.blends - 1) / 2;

    // Gait-timed locomotion: legs cycle through the gait tape, upper body
    // holds the family's level aim pose (aim frame zero, center pitch).
    let locomotion: [(&'static str, &SequenceInfo, &SequenceInfo); 4] = [
        ("idle", &gait_idle, &ref_aim),
        ("run", &gait_run, &ref_aim),
        ("crouchidle", &gait_crouch_idle, &crouch_aim),
        ("crouchrun", &gait_crouch_run, &crouch_aim),
    ];
    for (name, gait, aim) in locomotion {
        let poses = (0..gait.frames)
            .map(|frame| PoseSample::Composite {
                gait_seq: gait.index,
                gait_frame: frame,
                aim_seq: aim.index,
                aim_frame: 0,
                aim_blend: center_blend(aim),
            })
            .collect();
        plan.push(PosePlanEntry {
            name,
            source_label: gait.label.clone(),
            sequence_index: gait.index as u32,
            fps: gait.fps,
            frames: gait.frames as u32,
            looping: gait.looping,
            blends: 1,
            blend_type: [0, 0],
            blend_start: [0.0, 0.0],
            blend_end: [1.0, 0.0],
            poses,
        });
    }

    // Aim-timed actions: the family's authored shoot/reload tape (including
    // its nine-way pitch blends) plays over a stationary gait frame.
    let crouch_shoot = format!("crouch_shoot_{family}");
    let standing_shoot = format!("ref_shoot_{family}");
    let crouch_reload = format!("crouch_reload_{family}");
    let standing_reload = format!("ref_reload_{family}");
    let actions: [(&'static str, Vec<&str>, &SequenceInfo); 4] = [
        ("crouchshoot", vec![crouch_shoot.as_str()], &gait_crouch_idle),
        ("shoot", vec![standing_shoot.as_str()], &gait_idle),
        (
            "crouchreload",
            vec![crouch_reload.as_str()],
            &gait_crouch_idle,
        ),
        ("reload", vec![standing_reload.as_str()], &gait_idle),
    ];
    for (name, labels, gait) in actions {
        let Some(aim) = find_sequence(d, &labels) else {
            continue;
        };
        let mut poses = Vec::with_capacity(aim.blends * aim.frames);
        for blend in 0..aim.blends {
            for frame in 0..aim.frames {
                poses.push(PoseSample::Composite {
                    gait_seq: gait.index,
                    gait_frame: 0,
                    aim_seq: aim.index,
                    aim_frame: frame,
                    aim_blend: blend,
                });
            }
        }
        plan.push(PosePlanEntry {
            name,
            source_label: aim.label.clone(),
            sequence_index: aim.index as u32,
            fps: aim.fps,
            frames: aim.frames as u32,
            looping: aim.looping,
            blends: aim.blends as u32,
            blend_type: aim.blend_type,
            blend_start: aim.blend_start,
            blend_end: aim.blend_end,
            poses,
        });
    }

    // Death keeps its complete authored full-body sequence.
    if let Some(die) = find_sequence(
        d,
        &[
            "death1",
            "death2",
            "death3",
            "diesimple",
            "dieforward",
            "diebackward",
        ],
    ) {
        let poses = (0..die.frames)
            .map(|frame| PoseSample::Full {
                seq: die.index,
                frame,
                blend: 0,
            })
            .collect();
        plan.push(PosePlanEntry {
            name: "die",
            source_label: die.label.clone(),
            sequence_index: die.index as u32,
            fps: die.fps,
            frames: die.frames as u32,
            looping: die.looping,
            blends: 1,
            blend_type: [0, 0],
            blend_start: [0.0, 0.0],
            blend_end: [1.0, 0.0],
            poses,
        });
    }
    Some(plan)
}

fn plan_pose_matrices(
    d: &[u8],
    external_groups: &[&[u8]],
    numbones: usize,
    boneindex: usize,
    seqindex: usize,
    sample: &PoseSample,
) -> Result<Vec<Mat34>, String> {
    match sample {
        PoseSample::Full { seq, frame, blend } => anim_pose_matrices(
            d,
            external_groups,
            numbones,
            boneindex,
            seqindex,
            *seq,
            *frame,
            *blend,
        ),
        PoseSample::Composite {
            gait_seq,
            gait_frame,
            aim_seq,
            aim_frame,
            aim_blend,
        } => composite_pose_matrices(
            d,
            external_groups,
            numbones,
            boneindex,
            seqindex,
            *gait_seq,
            *gait_frame,
            *aim_seq,
            *aim_frame,
            *aim_blend,
        ),
    }
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
    body_value: usize,
) -> std::collections::BTreeMap<usize, (Vec<f32>, Vec<f32>, Vec<u8>)> {
    let skin_of = |skinref: usize| -> usize {
        let o = skinindex + skinref * 2;
        if o + 2 <= d.len() && skinref < numskinref {
            i16_at(d, o) as usize
        } else {
            0
        }
    };
    // Geometry, bucketed per texture
    let mut buckets: std::collections::BTreeMap<usize, (Vec<f32>, Vec<f32>, Vec<u8>)> = Default::default();
    for bp in 0..numbodyparts {
        let o = bodypartindex + bp * 76;
        let nummodels = i32_at(d, o + 64) as usize;
        let bodypart_base = i32_at(d, o + 68).max(1) as usize;
        let modelindex = i32_at(d, o + 72) as usize;
        let selected_model = if nummodels > 0 {
            (body_value / bodypart_base) % nummodels
        } else {
            0
        };
        for m in selected_model..(selected_model + nummodels.min(1)) {
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
                    let mut chain: Vec<([f32; 3], f32, f32, u8)> = Vec::with_capacity(count);
                    for k in 0..count {
                        let e = tri + k * 8;
                        let vi = i16_at(d, e) as usize;
                        let s = i16_at(d, e + 4) as f32;
                        let t = i16_at(d, e + 6) as f32;
                        let p = verts.get(vi).copied().unwrap_or([0.0; 3]);
                        let bone = if vi < numverts { d[vertinfoindex + vi] } else { 0 };
                        chain.push((p, (s + 0.5) / tw, (t + 0.5) / th, bone));
                    }
                    tri += count * 8;

                    let emit = |b: &mut (Vec<f32>, Vec<f32>, Vec<u8>), v: &([f32; 3], f32, f32, u8)| {
                        // GoldSrc -> three.js: (x, z, -y), scaled to world units
                        b.0.extend_from_slice(&[v.0[0] * 0.01, v.0[2] * 0.01, -v.0[1] * 0.01]);
                        b.1.extend_from_slice(&[v.1, v.2]);
                        b.2.push(v.3);
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

fn parse_mdl_body(d: &[u8], body_value: usize) -> Result<ParsedMdl, String> {
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
    let numskinfamilies = i32_at(d, 196).max(1) as usize;
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
        body_value,
    );

    let mut out = ParsedMdl {
        groups: Vec::new(),
        positions: Vec::new(),
        uvs: Vec::new(),
        pixels,
        seq_labels: sequence_labels(d),
        lower_body_mask: Vec::new(),
    };
    let gait_mask = gait_bone_mask(d);
    for (tex, (pos, uv, bones)) in buckets {
        let (name, w, h, off) = tex_meta[tex].clone();
        let skin_ref = (0..numskinref).find(|skin_ref| {
            let offset = skinindex + skin_ref * 2;
            offset + 2 <= d.len() && i16_at(d, offset) as usize == tex
        });
        let mut skin_textures = Vec::with_capacity(numskinfamilies);
        if let Some(skin_ref) = skin_ref {
            for family in 0..numskinfamilies {
                let offset = skinindex + (family * numskinref + skin_ref) * 2;
                if offset + 2 > d.len() {
                    break;
                }
                let texture_index = i16_at(d, offset) as usize;
                if let Some((skin_name, skin_width, skin_height, skin_offset)) =
                    tex_meta.get(texture_index)
                {
                    skin_textures.push(MdlTexture {
                        tex_name: skin_name.clone(),
                        width: *skin_width,
                        height: *skin_height,
                        pix_offset: *skin_offset,
                    });
                }
            }
        }
        out.groups.push(MdlGroup {
            tex_name: name,
            width: w,
            height: h,
            pix_offset: off,
            skin_textures,
            vert_start: (out.positions.len() / 3) as u32,
            vert_count: (pos.len() / 3) as u32,
        });
        out.positions.extend_from_slice(&pos);
        out.uvs.extend_from_slice(&uv);
        if let Some(mask) = &gait_mask {
            out.lower_body_mask.extend(bones.iter().map(|bone| {
                u8::from(mask.get(*bone as usize).copied().unwrap_or(false))
            }));
        }
    }
    Ok(out)
}

pub fn parse_mdl(d: &[u8]) -> Result<ParsedMdl, String> {
    parse_mdl_body(d, 0)
}

/// Enumerate every authored submodel of the single-bodypart layout used by
/// GoldSrc gib models. Refusing compound layouts keeps this export bounded and
/// prevents an incomplete bodygroup Cartesian product from looking valid.
pub fn parse_mdl_body_variants(d: &[u8]) -> Result<Vec<ParsedMdl>, String> {
    if d.len() < 244 || &d[0..4] != b"IDST" || i32_at(d, 4) != 10 {
        return Err("not a supported studio model".into());
    }
    let numbodyparts = i32_at(d, 204);
    let bodypartindex = i32_at(d, 208);
    if numbodyparts != 1 || bodypartindex < 0 {
        return Err(format!(
            "body-variant export requires exactly one bodypart, found {numbodyparts}"
        ));
    }
    let bodypartindex = bodypartindex as usize;
    if bodypartindex + 76 > d.len() {
        return Err("bodypart table out of range".into());
    }
    let variant_count = i32_at(d, bodypartindex + 64);
    if variant_count < 1 || variant_count > 64 {
        return Err(format!("implausible body variant count {variant_count}"));
    }
    (0..variant_count as usize)
        .map(|body_value| parse_mdl_body(d, body_value))
        .collect()
}

/// Parse a model AND bake idle/run animation frames (vertex positions per
/// frame, same order as ParsedMdl.positions).
pub fn parse_mdl_animated(d: &[u8]) -> Result<(ParsedMdl, Vec<MdlAnim>), String> {
    parse_mdl_animated_with_sequence_groups(d, &[])
}

/// Parse a player model using one original weapon activity family.
pub fn parse_mdl_animated_family(
    d: &[u8],
    family: &str,
) -> Result<(ParsedMdl, Vec<MdlAnim>), String> {
    parse_mdl_animated_family_with_sequence_groups(d, &[], family)
}

/// Parse a model and bake animation frames, including external IDSQ sequence
/// groups. Slice element zero supplies GoldSrc sequence group one.
pub fn parse_mdl_animated_with_sequence_groups(
    d: &[u8],
    external_groups: &[&[u8]],
) -> Result<(ParsedMdl, Vec<MdlAnim>), String> {
    parse_mdl_animated_family_with_sequence_groups(d, external_groups, "ak47")
}

/// Parse a model with external sequence groups while selecting the original
/// player action family authored for a particular p_ weapon.
pub fn parse_mdl_animated_family_with_sequence_groups(
    d: &[u8],
    external_groups: &[&[u8]],
    family: &str,
) -> Result<(ParsedMdl, Vec<MdlAnim>), String> {
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
            // Grenade viewmodels have idle/pullpin/throw/deploy, no gun actions.
            || label == "pullpin"
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
                    match anim_pose_matrices(
                        d,
                        external_groups,
                        numbones,
                        boneindex,
                        seqindex,
                        seq,
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
                                0,
                            );
                            for (_, (positions, _, _)) in buckets {
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

    // Player models with authored aim layers bake the source-faithful
    // gait-composited pose plan (legs = gait, upper body = aim family).
    if let Some(plan) = player_pose_plan(d, family) {
        for entry in plan {
            let mut data = Vec::new();
            let mut ok = true;
            for sample in &entry.poses {
                match plan_pose_matrices(
                    d,
                    external_groups,
                    numbones,
                    boneindex,
                    i32_at(d, 168) as usize,
                    sample,
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
                            0,
                        );
                        for (_, (pos, _, _)) in buckets {
                            data.extend_from_slice(&pos);
                        }
                    }
                    Err(_) => {
                        ok = false;
                        break;
                    }
                }
            }
            if ok && !data.is_empty() {
                anims.push(MdlAnim {
                    name: entry.name.to_string(),
                    source_label: entry.source_label,
                    sequence_index: entry.sequence_index,
                    fps: entry.fps,
                    frames: entry.frames,
                    looping: entry.looping,
                    blends: entry.blends,
                    blend_type: entry.blend_type,
                    blend_start: entry.blend_start,
                    blend_end: entry.blend_end,
                    data,
                });
            }
        }
        return Ok((base, anims));
    }

    let crouch_shoot = format!("crouch_shoot_{family}");
    let standing_shoot = format!("ref_shoot_{family}");
    let crouch_reload = format!("crouch_reload_{family}");
    let standing_reload = format!("ref_reload_{family}");
    let mut sequence_specs = vec![
        ("idle", vec!["idle1", "idle"]),
        ("run", vec!["run", "walk"]),
        ("crouchidle", vec!["crouch_idle", "crouchidle"]),
        ("crouchrun", vec!["crouchrun", "crouch_run"]),
        ("crouchshoot", vec![crouch_shoot.as_str()]),
        ("shoot", vec![standing_shoot.as_str()]),
        ("crouchreload", vec![crouch_reload.as_str()]),
        ("reload", vec![standing_reload.as_str()]),
        (
            "die",
            vec![
                "death1",
                "death2",
                "death3",
                "diesimple",
                "dieforward",
                "diebackward",
            ],
        ),
    ];
    if !external_groups.is_empty() {
        // Stock hostage/scientist models keep these gameplay activities in
        // IDSQ files. Preserve distinct walk and hit-reaction motions without
        // changing the established player-model export set.
        sequence_specs.push(("walk", vec!["walk", "walk_scared"]));
        sequence_specs.push(("flinch", vec!["flinch", "flinch1", "laflinch", "raflinch"]));
        sequence_specs.push(("panic", vec!["panic", "fear1", "fear2"]));
        sequence_specs.push(("acknowledge", vec!["yes"]));
        sequence_specs.push(("cower", vec!["cowering_in_corner"]));
        // Hostage/scientist corpses must end floor-flat: diesimple's held final
        // frame keeps both knees raised, while dieforward sprawls the body
        // flat across the ground plane like a settled GoldSrc corpse (and its
        // forward root motion falls into open space, not the wall behind).
        if let Some(die_spec) = sequence_specs.iter_mut().find(|(name, _)| *name == "die") {
            die_spec.1 = vec!["dieforward", "diebackward", "diesimple"];
        }
    }
    for (name, labels) in sequence_specs {
        let Some(sequence) = find_sequence(d, &labels) else {
            continue;
        };
        let mut data = Vec::new();
        let mut ok = true;
        for blend in 0..sequence.blends {
            for frame in 0..sequence.frames {
                match anim_pose_matrices(
                    d,
                    external_groups,
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
                            0,
                        );
                        for (_, (pos, _, _)) in buckets {
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
        // The standing ref_aim_ak47/ref_shoot_ak47 tapes in the stock player
        // MDLs pose the torso off the gait facing (their crouch twins are
        // fine); on screen the AK reads as a gun carried across the hips
        // instead of a shouldered rifle. Re-measured after the STUDIO_XR aim
        // blend interpolation landed, so it is not a blend-sampling artifact:
        // ref_aim_ak47 frame 0 center blend puts "Bip01 Spine" at yaw -61
        // degrees versus -12 for ref_aim_carbine and -11 for the idle gait,
        // and every one of the nine pitch blends renders with the same yaw
        // offset. The carbine family carries the correct two-handed forward
        // rifle aim, so the attached p_ak47 bakes through it. Mirrors
        // WEAPON_FAMILIES in game/scripts/mdl_character_model.gd.
        "ak47" | "aug" | "famas" | "galil" | "m4a1" | "sg552" => "carbine",
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
    for (_, (pos, _, _)) in walk_geometry(
        weapon,
        &remap(&bind),
        &w_texmeta,
        w_numbodyparts,
        w_bodypartindex,
        w_numskinref,
        w_skinindex,
        0,
    ) {
        positions.extend_from_slice(&pos);
    }

    // Use the same player activity family selected by each original weapon.
    // Reusing AK poses for pistols, SMGs, and grenades puts a correctly merged
    // p_ model in the wrong authored hand pose.
    let family = attached_weapon_family(weapon);
    let mut anims = Vec::new();
    if let Some(plan) = player_pose_plan(player, family) {
        // The weapon walks the exact composite matrices the player body bakes
        // for this family, so the gun stays in the animated hands.
        for entry in plan {
            let mut data = Vec::new();
            let mut ok = true;
            for sample in &entry.poses {
                match plan_pose_matrices(
                    player,
                    &[],
                    p_numbones,
                    p_boneindex,
                    i32_at(player, 168) as usize,
                    sample,
                ) {
                    Ok(mats) => {
                        for (_, (pos, _, _)) in walk_geometry(
                            weapon,
                            &remap(&mats),
                            &w_texmeta,
                            w_numbodyparts,
                            w_bodypartindex,
                            w_numskinref,
                            w_skinindex,
                            0,
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
            if ok && !data.is_empty() {
                anims.push(MdlAnim {
                    name: entry.name.to_string(),
                    source_label: entry.source_label,
                    sequence_index: entry.sequence_index,
                    fps: entry.fps,
                    frames: entry.frames,
                    looping: entry.looping,
                    blends: entry.blends,
                    blend_type: entry.blend_type,
                    blend_start: entry.blend_start,
                    blend_end: entry.blend_end,
                    data,
                });
            }
        }
    } else {
        let crouch_shoot = format!("crouch_shoot_{family}");
        let standing_shoot = format!("ref_shoot_{family}");
        let crouch_reload = format!("crouch_reload_{family}");
        let standing_reload = format!("ref_reload_{family}");
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
                        &[],
                        p_numbones,
                        p_boneindex,
                        i32_at(player, 168) as usize,
                        sequence.index,
                        frame,
                        blend,
                    ) {
                        Ok(mats) => {
                            for (_, (pos, _, _)) in walk_geometry(
                                weapon,
                                &remap(&mats),
                                &w_texmeta,
                                w_numbodyparts,
                                w_bodypartindex,
                                w_numskinref,
                                w_skinindex,
                                0,
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
    }

    let out = ParsedMdl {
        groups: base.groups,
        positions,
        uvs: base.uvs,
        pixels: base.pixels,
        // Attached animation metadata indexes the player skeleton's sequence
        // table, not the p_ weapon's (usually empty) table.
        seq_labels: sequence_labels(player),
        // Attached weapons never receive a lower-body overlay at runtime.
        lower_body_mask: Vec::new(),
    };
    Ok((out, anims))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn grenade_viewmodels_preserve_all_authored_sequences() {
        let models: [&[u8]; 3] = [
            include_bytes!("../../public/models/weapons/v_hegrenade.mdl"),
            include_bytes!("../../public/models/weapons/v_flashbang.mdl"),
            include_bytes!("../../public/models/weapons/v_smokegrenade.mdl"),
        ];
        for bytes in models {
            let (model, animations) = parse_mdl_animated(bytes).expect("grenade viewmodel");
            assert_eq!(animations.len(), model.seq_labels.len());
            for (index, animation) in animations.iter().enumerate() {
                assert_eq!(animation.sequence_index, index as u32);
                assert_eq!(animation.name, model.seq_labels[index]);
                assert!(animation.frames > 0);
                assert_eq!(
                    animation.data.len(),
                    animation.frames as usize * animation.blends as usize * model.positions.len()
                );
            }
            assert!(animations
                .iter()
                .any(|animation| animation.name == "pullpin"));
            assert!(animations.iter().any(|animation| animation.name == "throw"));
        }
    }

    const TERROR_MODEL: &[u8] = include_bytes!("../../public/models/player/terror/terror.mdl");
    const PLAYER_MODELS: [&[u8]; 8] = [
        TERROR_MODEL,
        include_bytes!("../../public/models/player/leet/leet.mdl"),
        include_bytes!("../../public/models/player/arctic/arctic.mdl"),
        include_bytes!("../../public/models/player/guerilla/guerilla.mdl"),
        include_bytes!("../../public/models/player/urban/urban.mdl"),
        include_bytes!("../../public/models/player/gsg9/gsg9.mdl"),
        include_bytes!("../../public/models/player/sas/sas.mdl"),
        include_bytes!("../../public/models/player/gign/gign.mdl"),
    ];

    #[test]
    fn player_gait_follows_both_leg_branches_after_the_spine() {
        for d in PLAYER_MODELS {
            let names = bone_names(d);
            let boneindex = i32_at(d, 144) as usize;
            let seqindex = i32_at(d, 168) as usize;
            let mask = gait_bone_mask(d).expect("player gait mask");
            // Independent oracle: Valve StudioSetupBones' ordered copy flag.
            let mut copy = true;
            for (b, name) in names.iter().enumerate() {
                let parent = i32_at(d, boneindex + b * 112 + 32);
                if name == "Bip01 Spine" {
                    copy = false;
                } else if parent >= 0 && names[parent as usize] == "Bip01 Pelvis" {
                    copy = true;
                }
                assert_eq!(mask[b], copy, "source gait ownership: {name}");
            }
            let left = names.iter().position(|n| n == "Bip01 L Foot").unwrap();
            let right = names.iter().position(|n| n == "Bip01 R Foot").unwrap();
            assert!(left > spine_bone_index(d).unwrap() && mask[left] && mask[right]);
            let aim = find_sequence(d, &["ref_aim_carbine"]).unwrap();
            for state in ["run", "crouchrun"] {
                let gait = find_sequence(d, &[state]).unwrap();
                let mut minimum = [f32::INFINITY; 2];
                let mut maximum = [f32::NEG_INFINITY; 2];
                for frame in 0..gait.frames {
                    let composite = composite_pose_matrices(d, &[], names.len(), boneindex,
                        seqindex, gait.index, frame, aim.index, 0, aim.blends / 2).unwrap();
                    let raw = anim_pose_matrices(d, &[], names.len(), boneindex,
                        seqindex, gait.index, frame, 0).unwrap();
                    for bone in [left, right] {
                        for axis in 0..3 {
                            for component in 0..4 {
                                assert!((composite[bone][axis][component] - raw[bone][axis][component]).abs() < 0.0001,
                                    "{state} frame {frame}: {} must retain authored gait", names[bone]);
                            }
                        }
                    }
                    for axis in 0..2 {
                        let separation = composite[left][axis][3] - composite[right][axis][3];
                        minimum[axis] = minimum[axis].min(separation);
                        maximum[axis] = maximum[axis].max(separation);
                    }
                }
                assert!((0..2).any(|axis| minimum[axis] < -5.0 && maximum[axis] > 5.0),
                    "{state}: feet must alternate which leads, got {minimum:?}..{maximum:?}");
            }
            let model = parse_mdl(d).unwrap();
            assert_eq!(model.lower_body_mask.len(), model.positions.len() / 3);
            assert!(model.lower_body_mask.contains(&0) && model.lower_body_mask.contains(&1));
            let floor = model.positions.chunks_exact(3).map(|p| p[1]).fold(f32::INFINITY, f32::min);
            assert!(model.positions.chunks_exact(3).zip(&model.lower_body_mask)
                .any(|(p, &mask)| mask == 1 && p[1] > floor + 0.34),
                "bone mask must retain thighs above the old height cutoff");
        }
    }
    const AK47_PLAYER_MODEL: &[u8] = include_bytes!("../../public/models/weapons/p_ak47.mdl");
    const C4_PLAYER_MODEL: &[u8] = include_bytes!("../../public/models/weapons/p_c4.mdl");
    const DEAGLE_PLAYER_MODEL: &[u8] = include_bytes!("../../public/models/weapons/p_deagle.mdl");
    const HOSTAGE_MODEL: &[u8] = include_bytes!("../../public/models/classic/hostage.mdl");
    const HOSTAGE_SEQUENCE_GROUPS: [&[u8]; 8] = [
        include_bytes!("../../public/models/classic/hostage01.mdl"),
        include_bytes!("../../public/models/classic/hostage02.mdl"),
        include_bytes!("../../public/models/classic/hostage03.mdl"),
        include_bytes!("../../public/models/classic/hostage04.mdl"),
        include_bytes!("../../public/models/classic/hostage05.mdl"),
        include_bytes!("../../public/models/classic/hostage06.mdl"),
        include_bytes!("../../public/models/classic/hostage07.mdl"),
        include_bytes!("../../public/models/classic/hostage08.mdl"),
    ];

    #[test]
    fn hostage_sequence_groups_preserve_authored_names_and_animation_data() {
        assert_eq!(
            external_sequence_group_names(HOSTAGE_MODEL).expect("hostage sequence groups"),
            (1..=8)
                .map(|group| format!("models\\hostage{group:02}.mdl"))
                .collect::<Vec<_>>()
        );

        let (model, animations) =
            parse_mdl_animated_with_sequence_groups(HOSTAGE_MODEL, &HOSTAGE_SEQUENCE_GROUPS)
                .expect("animated hostage model");
        assert_eq!(model.groups.len(), 2);
        assert_eq!(
            model.groups[0]
                .skin_textures
                .iter()
                .map(|texture| texture.tex_name.as_str())
                .collect::<Vec<_>>(),
            vec!["Hostage_Template1.BMP", "Hostage_Template2.BMP"]
        );
        assert_eq!(
            model.groups[1]
                .skin_textures
                .iter()
                .map(|texture| texture.tex_name.as_str())
                .collect::<Vec<_>>(),
            vec!["Face-Unwrap1.bmp", "Face-Unwrap2.bmp"]
        );
        for (name, source, frames, looping) in [
            ("idle", "idle1", 31, true),
            ("run", "run", 19, true),
            ("crouchidle", "crouch_idle", 11, true),
            ("die", "dieforward", 31, false),
            ("walk", "walk", 17, true),
            ("flinch", "flinch", 31, false),
            ("panic", "panic", 21, false),
            ("acknowledge", "yes", 31, false),
            ("cower", "cowering_in_corner", 131, true),
        ] {
            let animation = animations
                .iter()
                .find(|animation| animation.name == name)
                .unwrap_or_else(|| panic!("missing hostage {name} animation"));
            assert_eq!(animation.source_label, source);
            assert_eq!(animation.frames, frames);
            assert_eq!(animation.looping, looping);
            assert_eq!(
                animation.data.len(),
                model.positions.len() * frames as usize * animation.blends as usize
            );
            let first_frame = &animation.data[..model.positions.len()];
            let comparison_offset = (frames as usize / 2) * model.positions.len();
            let comparison_frame =
                &animation.data[comparison_offset..comparison_offset + model.positions.len()];
            assert!(
                first_frame
                    .iter()
                    .zip(comparison_frame)
                    .any(|(first, comparison)| (first - comparison).abs() >= 0.0001),
                "hostage {name} collapsed to a static pose"
            );
        }
    }

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
    fn c4_player_family_matches_the_attached_c4_action_tape() {
        let (_, body_animations) =
            parse_mdl_animated_family(TERROR_MODEL, "c4").expect("C4 player body");
        let (_, weapon_animations) =
            parse_mdl_attached(TERROR_MODEL, C4_PLAYER_MODEL).expect("attached C4");
        for (name, source, frames) in [
            ("shoot", "ref_shoot_c4", 151),
            ("crouchshoot", "crouch_shoot_c4", 121),
        ] {
            let body = body_animations
                .iter()
                .find(|animation| animation.name == name)
                .unwrap_or_else(|| panic!("missing body {name}"));
            let weapon = weapon_animations
                .iter()
                .find(|animation| animation.name == name)
                .unwrap_or_else(|| panic!("missing attached {name}"));
            assert_eq!(body.source_label, source);
            assert_eq!(body.frames, frames);
            assert_eq!(body.fps, weapon.fps);
            assert_eq!(body.frames, weapon.frames);
            assert_eq!(body.blends, weapon.blends);
        }
    }

    #[test]
    fn attached_weapon_preserves_player_action_sequences() {
        let (model, animations) =
            parse_mdl_attached(TERROR_MODEL, AK47_PLAYER_MODEL).expect("attached AK-47");
        // The AK bakes on the carbine family (see attached_weapon_family), so
        // these are the carbine tape's frame counts, not ref_shoot_ak47's.
        for (name, frames, blends) in [
            ("shoot", 5, 9),
            ("crouchshoot", 5, 9),
            ("reload", 61, 1),
            ("crouchreload", 61, 1),
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
        // p_ak47 deliberately resolves to the carbine family: the stock
        // ref_aim_ak47/ref_shoot_ak47 tapes pose the torso off the gait facing
        // at every pitch blend, so the rifle renders hip-carried instead of
        // shouldered. attached_weapon_family documents the measurement.
        assert_eq!(attached_weapon_family(AK47_PLAYER_MODEL), "carbine");
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
