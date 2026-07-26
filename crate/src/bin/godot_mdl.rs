use cs16_demo_parser::mdl::parse_mdl;
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
        "Usage: {program} <model.mdl> <output-directory>\n\
         Example: {program} public/models/weapons/v_ak47.mdl game/generated/weapons/ak47"
    )
}

fn run() -> Result<(), String> {
    let arguments: Vec<String> = env::args().collect();
    if arguments.len() != 3 {
        return Err(usage(
            arguments.first().map(String::as_str).unwrap_or("godot_mdl"),
        ));
    }
    let model_path = PathBuf::from(&arguments[1]);
    let output_path = PathBuf::from(&arguments[2]);
    let texture_path = output_path.join("textures");
    fs::create_dir_all(&texture_path).map_err(|error| error.to_string())?;

    let bytes = fs::read(&model_path)
        .map_err(|error| format!("could not read {}: {error}", model_path.display()))?;
    let parsed = parse_mdl(&bytes)?;
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
                let pixels = parsed
                    .pixels
                    .get(offset..offset + count)
                    .ok_or_else(|| format!("texture {} points outside pixel buffer", group.tex_name))?;
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

    let export = ModelExport {
        format: "protocol47-mdl",
        version: 1,
        groups,
        positions: &parsed.positions,
        uvs: &parsed.uvs,
        sequences: &parsed.seq_labels,
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

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
