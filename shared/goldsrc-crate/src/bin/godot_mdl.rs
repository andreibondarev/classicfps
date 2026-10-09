use cs16_demo_parser::mdl::{
    external_sequence_group_names, parse_mdl, parse_mdl_animated_family_with_sequence_groups,
    parse_mdl_animated_with_sequence_groups, parse_mdl_attached, parse_mdl_body_variants, MdlAnim,
    ParsedMdl,
};
use serde::Serialize;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Serialize)]
struct ExportGroup {
    name: String,
    vert_start: u32,
    vert_count: u32,
    texture: Option<String>,
    skins: Vec<String>,
}

#[derive(Serialize)]
struct ModelExport<'a> {
    format: &'static str,
    version: u32,
    groups: Vec<ExportGroup>,
    positions: &'a [f32],
    #[serde(skip_serializing_if = "<[u8]>::is_empty")]
    lower_body_mask: &'a [u8],
    uvs: &'a [f32],
    sequences: &'a [String],
    animations: Vec<AnimationExport>,
    /// Animated models store rigid bone transforms per pose instead of baked
    /// vertex frames; the runtime rebuilds frames from these on load.
    #[serde(skip_serializing_if = "Option::is_none")]
    frame_format: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    bone_count: Option<u32>,
    #[serde(skip_serializing_if = "<[u8]>::is_empty")]
    vertex_bones: &'a [u8],
    #[serde(skip_serializing_if = "Option::is_none")]
    skin_file: Option<&'static str>,
}

/// Largest allowed difference between a baked vertex and the same vertex
/// rebuilt from its bone transform, in output units (0.01 GoldSrc units).
const BONE_REBUILD_TOLERANCE: f32 = 2e-4;

/// Rebuild every pose from `bone_poses` and compare with the baked frames, so
/// the exported bone format is proven equivalent to the vertex data it replaces.
fn verify_bone_rebuild(parsed: &ParsedMdl, animation: &MdlAnim) -> Result<f32, String> {
    let vertex_count = parsed.positions.len() / 3;
    let bone_count = animation.bone_count as usize;
    let pose_stride = bone_count * 12;
    if parsed.vertex_bones.len() != vertex_count || parsed.skin_local.len() != vertex_count * 3 {
        return Err(format!("animation {} has no rigid skin", animation.name));
    }
    let poses = animation.frames as usize * animation.blends as usize;
    if bone_count == 0 || animation.bone_poses.len() != poses * pose_stride {
        return Err(format!(
            "animation {} has {} bone floats for {} poses of {} bones",
            animation.name,
            animation.bone_poses.len(),
            poses,
            bone_count
        ));
    }
    let mut max_error = 0f32;
    for pose in 0..poses {
        let transforms = &animation.bone_poses[pose * pose_stride..(pose + 1) * pose_stride];
        for vertex in 0..vertex_count {
            let local = &parsed.skin_local[vertex * 3..vertex * 3 + 3];
            let bone = parsed.vertex_bones[vertex] as usize;
            let rebuilt = if bone < bone_count {
                let m = &transforms[bone * 12..bone * 12 + 12];
                [
                    m[0] * local[0] + m[1] * local[1] + m[2] * local[2] + m[3],
                    m[4] * local[0] + m[5] * local[1] + m[6] * local[2] + m[7],
                    m[8] * local[0] + m[9] * local[1] + m[10] * local[2] + m[11],
                ]
            } else {
                [local[0], local[1], local[2]]
            };
            let baked = &animation.data[(pose * vertex_count + vertex) * 3..][..3];
            for axis in 0..3 {
                max_error = max_error.max((rebuilt[axis] - baked[axis]).abs());
            }
        }
    }
    if max_error > BONE_REBUILD_TOLERANCE {
        return Err(format!(
            "animation {} rebuilds from bones with error {max_error}",
            animation.name
        ));
    }
    Ok(max_error)
}

fn write_f32(path: &Path, values: &[f32]) -> Result<(), String> {
    let mut bytes = Vec::with_capacity(values.len() * 4);
    for value in values {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    fs::write(path, bytes).map_err(|error| format!("could not write {}: {error}", path.display()))
}

#[derive(Serialize)]
struct AnimationExport {
    name: String,
    source_label: String,
    sequence_index: u32,
    fps: f32,
    frames: u32,
    looping: bool,
    blends: u32,
    blend_type: [i32; 2],
    blend_start: [f32; 2],
    blend_end: [f32; 2],
    file: String,
}

#[derive(Serialize)]
struct BodyVariantManifest {
    format: &'static str,
    version: u32,
    source_model: String,
    variants: Vec<String>,
}

fn safe_name(name: &str) -> String {
    let cleaned: String = name
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || character == '_' || character == '-' {
                character.to_ascii_lowercase()
            } else {
                '_'
            }
        })
        .collect();
    let trimmed = cleaned.trim_matches('_');
    if trimmed.is_empty() {
        "texture".to_string()
    } else {
        trimmed.to_string()
    }
}

fn write_tga(path: &Path, width: u32, height: u32, rgba: &[u8]) -> Result<(), String> {
    if width == 0 || height == 0 || rgba.len() != width as usize * height as usize * 4 {
        return Err(format!(
            "invalid texture {}x{} with {} bytes",
            width,
            height,
            rgba.len()
        ));
    }
    let mut file = fs::File::create(path).map_err(|error| error.to_string())?;
    let mut header = [0u8; 18];
    header[2] = 2;
    header[12..14].copy_from_slice(&(width as u16).to_le_bytes());
    header[14..16].copy_from_slice(&(height as u16).to_le_bytes());
    header[16] = 32;
    header[17] = 0x28;
    file.write_all(&header).map_err(|error| error.to_string())?;
    for pixel in rgba.chunks_exact(4) {
        file.write_all(&[pixel[2], pixel[1], pixel[0], pixel[3]])
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn usage(program: &str) -> String {
    format!(
        "Usage:\n\
         {program} <model.mdl> <output-directory>\n\
         {program} --body-variants <gibs.mdl> <output-directory>\n\
         {program} --animated <player.mdl> <output-directory>\n\
         {program} --animated-family <family> <player.mdl> <output-directory>\n\
         {program} --attached <player.mdl> <weapon.mdl> <output-directory>"
    )
}

fn export_model(
    parsed: &ParsedMdl,
    anims: &[MdlAnim],
    model_path: &Path,
    output_path: &Path,
) -> Result<(), String> {
    let texture_path = output_path.join("textures");
    fs::create_dir_all(&texture_path).map_err(|error| error.to_string())?;
    let animation_path = output_path.join("animations");
    if animation_path.is_dir() {
        // Drop tapes from earlier exports (including the old baked-vertex
        // .f32 frames) so renamed or removed animations cannot linger.
        fs::remove_dir_all(&animation_path).map_err(|error| error.to_string())?;
    }
    if !anims.is_empty() {
        fs::create_dir_all(&animation_path).map_err(|error| error.to_string())?;
    }
    let mut texture_files: HashMap<(i64, u32, u32), String> = HashMap::new();
    let mut groups = Vec::with_capacity(parsed.groups.len());

    for (index, group) in parsed.groups.iter().enumerate() {
        let texture = if group.pix_offset >= 0 && group.width > 0 && group.height > 0 {
            let key = (group.pix_offset, group.width, group.height);
            if let Some(existing) = texture_files.get(&key) {
                Some(existing.clone())
            } else {
                let filename = format!("{index:03}_{}.tga", safe_name(&group.tex_name));
                let offset = group.pix_offset as usize;
                let count = group.width as usize * group.height as usize * 4;
                let pixels = parsed.pixels.get(offset..offset + count).ok_or_else(|| {
                    format!("texture {} points outside pixel buffer", group.tex_name)
                })?;
                write_tga(
                    &texture_path.join(&filename),
                    group.width,
                    group.height,
                    pixels,
                )?;
                let relative = format!("textures/{filename}");
                texture_files.insert(key, relative.clone());
                Some(relative)
            }
        } else {
            None
        };
        let mut skins = Vec::with_capacity(group.skin_textures.len());
        for (family, skin) in group.skin_textures.iter().enumerate() {
            if skin.pix_offset < 0 || skin.width == 0 || skin.height == 0 {
                continue;
            }
            let key = (skin.pix_offset, skin.width, skin.height);
            let relative = if let Some(existing) = texture_files.get(&key) {
                existing.clone()
            } else {
                let filename = format!("{index:03}_skin{family}_{}.tga", safe_name(&skin.tex_name));
                let offset = skin.pix_offset as usize;
                let count = skin.width as usize * skin.height as usize * 4;
                let pixels = parsed.pixels.get(offset..offset + count).ok_or_else(|| {
                    format!("skin texture {} points outside pixel buffer", skin.tex_name)
                })?;
                write_tga(
                    &texture_path.join(&filename),
                    skin.width,
                    skin.height,
                    pixels,
                )?;
                let relative = format!("textures/{filename}");
                texture_files.insert(key, relative.clone());
                relative
            };
            skins.push(relative);
        }
        groups.push(ExportGroup {
            name: group.tex_name.clone(),
            vert_start: group.vert_start,
            vert_count: group.vert_count,
            texture,
            skins,
        });
    }

    let mut animations = Vec::new();
    let mut bone_count = None;
    let mut max_rebuild_error = 0f32;
    for (index, animation) in anims.iter().enumerate() {
        if animation.frames == 0 || animation.data.is_empty() {
            continue;
        }
        let expected =
            parsed.positions.len() * animation.frames as usize * animation.blends as usize;
        if animation.data.len() != expected {
            return Err(format!(
                "animation {} has {} floats; expected {}",
                animation.name,
                animation.data.len(),
                expected
            ));
        }
        let error = verify_bone_rebuild(parsed, animation)?;
        max_rebuild_error = max_rebuild_error.max(error);
        if bone_count.is_some_and(|count| count != animation.bone_count) {
            return Err(format!("animation {} changes the bone count", animation.name));
        }
        bone_count = Some(animation.bone_count);
        let filename = format!("{index:02}_{}.bones.f32", safe_name(&animation.name));
        write_f32(&animation_path.join(&filename), &animation.bone_poses)?;
        animations.push(AnimationExport {
            name: animation.name.clone(),
            source_label: animation.source_label.clone(),
            sequence_index: animation.sequence_index,
            fps: animation.fps,
            frames: animation.frames,
            looping: animation.looping,
            blends: animation.blends,
            blend_type: animation.blend_type,
            blend_start: animation.blend_start,
            blend_end: animation.blend_end,
            file: format!("animations/{filename}"),
        });
    }

    let animated = !animations.is_empty();
    let skin_path = output_path.join("skin.f32");
    if animated {
        write_f32(&skin_path, &parsed.skin_local)?;
    } else if skin_path.is_file() {
        fs::remove_file(&skin_path).map_err(|error| error.to_string())?;
    }
    let export = ModelExport {
        format: "protocol47-mdl",
        version: if animated { 4 } else { 1 },
        frame_format: animated.then_some("rigid_bones"),
        bone_count,
        vertex_bones: if animated { &parsed.vertex_bones } else { &[] },
        skin_file: animated.then_some("skin.f32"),
        groups,
        positions: &parsed.positions,
        lower_body_mask: &parsed.lower_body_mask,
        uvs: &parsed.uvs,
        sequences: &parsed.seq_labels,
        animations,
    };
    let json = serde_json::to_vec(&export).map_err(|error| error.to_string())?;
    fs::write(output_path.join("model.json"), json).map_err(|error| error.to_string())?;
    println!(
        "Exported {}: {} vertices, {} surfaces, max bone rebuild error {:.2e}",
        model_path.display(),
        parsed.positions.len() / 3,
        parsed.groups.len(),
        max_rebuild_error
    );
    Ok(())
}

fn read_model(path: &Path) -> Result<Vec<u8>, String> {
    fs::read(path).map_err(|error| format!("could not read {}: {error}", path.display()))
}

fn read_external_sequence_groups(model_path: &Path, model: &[u8]) -> Result<Vec<Vec<u8>>, String> {
    let model_directory = model_path.parent().unwrap_or_else(|| Path::new("."));
    external_sequence_group_names(model)?
        .into_iter()
        .enumerate()
        .map(|(index, authored_name)| {
            // GoldSrc model paths are authored with Windows separators. Studio
            // sequence groups are resolved beside the owning model, regardless
            // of the embedded "models\\" prefix.
            let normalized_name = authored_name.replace('\\', "/");
            let filename = normalized_name
                .rsplit('/')
                .next()
                .filter(|name| !name.is_empty())
                .ok_or_else(|| format!("sequence group {} has an invalid filename", index + 1))?;
            read_model(&model_directory.join(filename))
        })
        .collect()
}

fn run() -> Result<(), String> {
    let arguments: Vec<String> = env::args().collect();
    let program = arguments.first().map(String::as_str).unwrap_or("godot_mdl");
    match arguments.as_slice() {
        [_, model, output] => {
            let model_path = PathBuf::from(model);
            let bytes = read_model(&model_path)?;
            let parsed = parse_mdl(&bytes)?;
            export_model(&parsed, &[], &model_path, Path::new(output))
        }
        [_, mode, model, output] if mode == "--animated" => {
            let model_path = PathBuf::from(model);
            let bytes = read_model(&model_path)?;
            let sequence_groups = read_external_sequence_groups(&model_path, &bytes)?;
            let sequence_group_slices: Vec<&[u8]> = sequence_groups
                .iter()
                .map(|group| group.as_slice())
                .collect();
            let (parsed, animations) =
                parse_mdl_animated_with_sequence_groups(&bytes, &sequence_group_slices)?;
            export_model(&parsed, &animations, &model_path, Path::new(output))
        }
        [_, mode, model, output] if mode == "--body-variants" => {
            let model_path = PathBuf::from(model);
            let bytes = read_model(&model_path)?;
            let variants = parse_mdl_body_variants(&bytes)?;
            let output_path = Path::new(output);
            let mut variant_paths = Vec::with_capacity(variants.len());
            for (index, parsed) in variants.iter().enumerate() {
                let relative = format!("variants/{index:03}/model.json");
                export_model(
                    parsed,
                    &[],
                    &model_path,
                    &output_path.join(format!("variants/{index:03}")),
                )?;
                variant_paths.push(relative);
            }
            let manifest = BodyVariantManifest {
                format: "protocol47-mdl-body-variants",
                version: 1,
                source_model: model_path
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or(model)
                    .to_string(),
                variants: variant_paths,
            };
            let json = serde_json::to_vec(&manifest).map_err(|error| error.to_string())?;
            fs::write(output_path.join("variants.json"), json)
                .map_err(|error| error.to_string())?;
            println!(
                "Exported {} authored body variants for {}",
                variants.len(),
                model_path.display()
            );
            Ok(())
        }
        [_, mode, family, model, output] if mode == "--animated-family" => {
            let model_path = PathBuf::from(model);
            let bytes = read_model(&model_path)?;
            let sequence_groups = read_external_sequence_groups(&model_path, &bytes)?;
            let sequence_group_slices: Vec<&[u8]> = sequence_groups
                .iter()
                .map(|group| group.as_slice())
                .collect();
            let (parsed, animations) = parse_mdl_animated_family_with_sequence_groups(
                &bytes,
                &sequence_group_slices,
                family,
            )?;
            export_model(&parsed, &animations, &model_path, Path::new(output))
        }
        [_, mode, player, weapon, output] if mode == "--attached" => {
            let player_path = PathBuf::from(player);
            let weapon_path = PathBuf::from(weapon);
            let player_bytes = read_model(&player_path)?;
            let weapon_bytes = read_model(&weapon_path)?;
            let (parsed, animations) = parse_mdl_attached(&player_bytes, &weapon_bytes)?;
            export_model(&parsed, &animations, &weapon_path, Path::new(output))
        }
        _ => Err(usage(program)),
    }
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
