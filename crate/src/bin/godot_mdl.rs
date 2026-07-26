use cs16_demo_parser::mdl::{
    parse_mdl, parse_mdl_animated, parse_mdl_attached, MdlAnim, ParsedMdl,
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
}

#[derive(Serialize)]
struct ModelExport<'a> {
    format: &'static str,
    version: u32,
    groups: Vec<ExportGroup>,
    positions: &'a [f32],
    uvs: &'a [f32],
    sequences: &'a [String],
    animations: Vec<AnimationExport>,
}

#[derive(Serialize)]
struct AnimationExport {
    name: String,
    fps: f32,
    frames: u32,
    file: String,
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
         {program} --animated <player.mdl> <output-directory>\n\
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
        groups.push(ExportGroup {
            name: group.tex_name.clone(),
            vert_start: group.vert_start,
            vert_count: group.vert_count,
            texture,
        });
    }

    let mut animations = Vec::new();
    for (index, animation) in anims.iter().enumerate() {
        if animation.frames == 0 || animation.data.is_empty() {
            continue;
        }
        let expected = parsed.positions.len() * animation.frames as usize;
        if animation.data.len() != expected {
            return Err(format!(
                "animation {} has {} floats; expected {}",
                animation.name,
                animation.data.len(),
                expected
            ));
        }
        let filename = format!("{index:02}_{}.f32", safe_name(&animation.name));
        let mut bytes = Vec::with_capacity(animation.data.len() * 4);
        for value in &animation.data {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        fs::write(animation_path.join(&filename), bytes).map_err(|error| error.to_string())?;
        animations.push(AnimationExport {
            name: animation.name.clone(),
            fps: animation.fps,
            frames: animation.frames,
            file: format!("animations/{filename}"),
        });
    }

    let export = ModelExport {
        format: "protocol47-mdl",
        version: if animations.is_empty() { 1 } else { 2 },
        groups,
        positions: &parsed.positions,
        uvs: &parsed.uvs,
        sequences: &parsed.seq_labels,
        animations,
    };
    let json = serde_json::to_vec(&export).map_err(|error| error.to_string())?;
    fs::write(output_path.join("model.json"), json).map_err(|error| error.to_string())?;
    println!(
        "Exported {}: {} vertices, {} surfaces",
        model_path.display(),
        parsed.positions.len() / 3,
        parsed.groups.len()
    );
    Ok(())
}

fn read_model(path: &Path) -> Result<Vec<u8>, String> {
    fs::read(path).map_err(|error| format!("could not read {}: {error}", path.display()))
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
            let (parsed, animations) = parse_mdl_animated(&bytes)?;
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
