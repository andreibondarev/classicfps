use cs16_demo_parser::bsp::{parse_wad, BspParser};
use serde::Serialize;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Serialize)]
struct ExportGroup {
    model_index: u32,
    name: String,
    vert_start: u32,
    vert_count: u32,
    texture: Option<String>,
    transparent: bool,
    liquid: bool,
}

#[derive(Serialize)]
struct MapExport<'a> {
    format: &'static str,
    version: u32,
    groups: Vec<ExportGroup>,
    positions: &'a [f32],
    normals: &'a [f32],
    colors: &'a [f32],
    uvs: &'a [f32],
    entities: &'a [cs16_demo_parser::types::BspEntity],
    bounds_min: &'a cs16_demo_parser::types::Vec3,
    bounds_max: &'a cs16_demo_parser::types::Vec3,
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
    if width > u16::MAX as u32 || height > u16::MAX as u32 {
        return Err(format!("texture too large for TGA: {}x{}", width, height));
    }
    let mut file = fs::File::create(path).map_err(|error| error.to_string())?;
    let mut header = [0u8; 18];
    header[2] = 2; // uncompressed true-color
    header[12..14].copy_from_slice(&(width as u16).to_le_bytes());
    header[14..16].copy_from_slice(&(height as u16).to_le_bytes());
    header[16] = 32;
    header[17] = 0x28; // top-left origin + 8 alpha bits
    file.write_all(&header).map_err(|error| error.to_string())?;
    for pixel in rgba.chunks_exact(4) {
        file.write_all(&[pixel[2], pixel[1], pixel[0], pixel[3]])
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn usage(program: &str) -> String {
    format!(
        "Usage: {program} <map.bsp> <output-directory> [texture.wad ...]\n\
         Example: {program} public/maps/de_dust2.bsp game/generated/de_dust2 \
         public/wads/cstrike.wad public/wads/cs_dust.wad"
    )
}

fn run() -> Result<(), String> {
    let arguments: Vec<String> = env::args().collect();
    if arguments.len() < 3 {
        return Err(usage(
            arguments.first().map(String::as_str).unwrap_or("godot_bsp"),
        ));
    }
    let bsp_path = PathBuf::from(&arguments[1]);
    let output_path = PathBuf::from(&arguments[2]);
    let texture_path = output_path.join("textures");
    fs::create_dir_all(&texture_path).map_err(|error| error.to_string())?;

    let bsp_bytes = fs::read(&bsp_path)
        .map_err(|error| format!("could not read {}: {error}", bsp_path.display()))?;
    let mut wad_textures = HashMap::new();
    for wad_argument in &arguments[3..] {
        let wad_path = PathBuf::from(wad_argument);
        let wad_bytes = fs::read(&wad_path)
            .map_err(|error| format!("could not read {}: {error}", wad_path.display()))?;
        parse_wad(&wad_bytes, &mut wad_textures);
    }

    let mut parser = BspParser::new(&bsp_bytes);
    let parsed = parser.parse_textured(&wad_textures)?;
    let mut texture_files: HashMap<(i64, u32, u32), String> = HashMap::new();
    let mut export_groups = Vec::with_capacity(parsed.groups.len());

    for (group_index, group) in parsed.groups.iter().enumerate() {
        let texture = if group.pix_offset >= 0 && group.width > 0 && group.height > 0 {
            let key = (group.pix_offset, group.width, group.height);
            if let Some(existing) = texture_files.get(&key) {
                Some(existing.clone())
            } else {
                let filename = format!("{:03}_{}.tga", group_index, safe_name(&group.name));
                let offset = group.pix_offset as usize;
                let byte_count = group.width as usize * group.height as usize * 4;
                let pixels = parsed
                    .pixels
                    .get(offset..offset + byte_count)
                    .ok_or_else(|| format!("texture {} points outside pixel buffer", group.name))?;
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
        let lower = group.name.to_ascii_lowercase();
        export_groups.push(ExportGroup {
            model_index: group.model_index,
            name: group.name.clone(),
            vert_start: group.vert_start,
            vert_count: group.vert_count,
            texture,
            transparent: group.name.starts_with('{'),
            liquid: lower.starts_with('!')
                || lower.contains("water")
                || lower.contains("slime")
                || lower.contains("lava"),
        });
    }

    let export = MapExport {
        format: "protocol47-bsp",
        version: 1,
        groups: export_groups,
        positions: &parsed.positions,
        normals: &parsed.normals,
        colors: &parsed.colors,
        uvs: &parsed.uvs,
        entities: &parsed.entities,
        bounds_min: &parsed.bounds_min,
        bounds_max: &parsed.bounds_max,
    };
    let json = serde_json::to_vec(&export).map_err(|error| error.to_string())?;
    fs::write(output_path.join("map.json"), json).map_err(|error| error.to_string())?;

    println!(
        "GODOT_BSP_EXPORT_PASS map={} vertices={} groups={} textures={} entities={}",
        bsp_path.display(),
        parsed.positions.len() / 3,
        parsed.groups.len(),
        texture_files.len(),
        parsed.entities.len(),
    );
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
