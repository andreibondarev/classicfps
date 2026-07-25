use crate::types::*;
use byteorder::{LittleEndian, ReadBytesExt};
use std::io::{Cursor, Read, Seek, SeekFrom};

const LUMP_ENTITIES: usize = 0;
const LUMP_PLANES: usize = 1;
const LUMP_TEXTURES: usize = 2;
const LUMP_VERTICES: usize = 3;
const LUMP_TEXINFO: usize = 6;
const LUMP_FACES: usize = 7;
const LUMP_LIGHTING: usize = 8;
const LUMP_EDGES: usize = 12;
const LUMP_SURFEDGES: usize = 13;
const LUMP_MODELS: usize = 14;
const LUMP_COUNT: usize = 15;

struct Lump {
    offset: i32,
    length: i32,
}

struct Plane {
    normal: Vec3,
    dist: f32,
}

struct Face {
    plane_index: u16,
    plane_side: u16,
    first_edge: i32,
    num_edges: u16,
    texinfo_index: u16,
    lightmap_offset: i32,
}

struct TexInfo {
    s: [f32; 4],
    t: [f32; 4],
    miptex_index: i32,
    flags: i32,
}

struct MipTex {
    name: String,
}

struct Model {
    mins: Vec3,
    maxs: Vec3,
    first_face: i32,
    num_faces: i32,
}

pub struct BspParser<'a> {
    data: Cursor<&'a [u8]>,
}

impl<'a> BspParser<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Self {
            data: Cursor::new(data),
        }
    }

    pub fn parse(&mut self) -> Result<ParsedBsp, String> {
        // Read header
        let version = self
            .data
            .read_i32::<LittleEndian>()
            .map_err(|e| e.to_string())?;
        if version != 30 {
            return Err(format!("Unsupported BSP version: {}", version));
        }

        // Read lump directory
        let mut lumps = Vec::with_capacity(LUMP_COUNT);
        for _ in 0..LUMP_COUNT {
            lumps.push(Lump {
                offset: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                length: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
            });
        }

        // Parse components
        let vertices = self.parse_vertices(&lumps[LUMP_VERTICES])?;
        let edges = self.parse_edges(&lumps[LUMP_EDGES])?;
        let surfedges = self.parse_surfedges(&lumps[LUMP_SURFEDGES])?;
        let planes = self.parse_planes(&lumps[LUMP_PLANES])?;
        let faces = self.parse_faces(&lumps[LUMP_FACES])?;
        let texinfos = self.parse_texinfos(&lumps[LUMP_TEXINFO])?;
        let textures = self.parse_textures(&lumps[LUMP_TEXTURES])?;
        let models = self.parse_models(&lumps[LUMP_MODELS])?;
        let entities = self.parse_entities(&lumps[LUMP_ENTITIES])?;
        let lighting = self.read_raw_lump(&lumps[LUMP_LIGHTING])?;

        // Build merged geometry
        let (out_vertices, out_normals, out_colors, bounds_min, bounds_max) = self.build_geometry(
            &vertices, &edges, &surfedges, &planes, &faces, &texinfos, &textures, &models,
            &lighting,
        )?;

        Ok(ParsedBsp {
            vertices: out_vertices,
            normals: out_normals,
            colors: out_colors,
            entities,
            bounds_min,
            bounds_max,
        })
    }

    fn read_raw_lump(&mut self, lump: &Lump) -> Result<Vec<u8>, String> {
        if lump.length <= 0 {
            return Ok(Vec::new());
        }
        self.data
            .seek(SeekFrom::Start(lump.offset as u64))
            .map_err(|e| e.to_string())?;
        let mut buf = vec![0u8; lump.length as usize];
        self.data.read_exact(&mut buf).map_err(|e| e.to_string())?;
        Ok(buf)
    }

    fn parse_vertices(&mut self, lump: &Lump) -> Result<Vec<Vec3>, String> {
        let count = lump.length / 12;
        let mut vertices = Vec::with_capacity(count as usize);
        self.data
            .seek(SeekFrom::Start(lump.offset as u64))
            .map_err(|e| e.to_string())?;

        for _ in 0..count {
            vertices.push(Vec3::new(
                self.data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                self.data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                self.data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
            ));
        }

        Ok(vertices)
    }

    fn parse_edges(&mut self, lump: &Lump) -> Result<Vec<(u16, u16)>, String> {
        let count = lump.length / 4;
        let mut edges = Vec::with_capacity(count as usize);
        self.data
            .seek(SeekFrom::Start(lump.offset as u64))
            .map_err(|e| e.to_string())?;

        for _ in 0..count {
            edges.push((
                self.data
                    .read_u16::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                self.data
                    .read_u16::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
            ));
        }

        Ok(edges)
    }

    fn parse_surfedges(&mut self, lump: &Lump) -> Result<Vec<i32>, String> {
        let count = lump.length / 4;
        let mut surfedges = Vec::with_capacity(count as usize);
        self.data
            .seek(SeekFrom::Start(lump.offset as u64))
            .map_err(|e| e.to_string())?;

        for _ in 0..count {
            surfedges.push(
                self.data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
            );
        }

        Ok(surfedges)
    }

    fn parse_planes(&mut self, lump: &Lump) -> Result<Vec<Plane>, String> {
        let count = lump.length / 20;
        let mut planes = Vec::with_capacity(count as usize);
        self.data
            .seek(SeekFrom::Start(lump.offset as u64))
            .map_err(|e| e.to_string())?;

        for _ in 0..count {
            planes.push(Plane {
                normal: Vec3::new(
                    self.data
                        .read_f32::<LittleEndian>()
                        .map_err(|e| e.to_string())?,
                    self.data
                        .read_f32::<LittleEndian>()
                        .map_err(|e| e.to_string())?,
                    self.data
                        .read_f32::<LittleEndian>()
                        .map_err(|e| e.to_string())?,
                ),
                dist: self
                    .data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
            });
            self.data
                .read_i32::<LittleEndian>()
                .map_err(|e| e.to_string())?; // type
        }

        Ok(planes)
    }

    fn parse_faces(&mut self, lump: &Lump) -> Result<Vec<Face>, String> {
        let count = lump.length / 20;
        let mut faces = Vec::with_capacity(count as usize);
        self.data
            .seek(SeekFrom::Start(lump.offset as u64))
            .map_err(|e| e.to_string())?;

        for _ in 0..count {
            faces.push(Face {
                plane_index: self
                    .data
                    .read_u16::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                plane_side: self
                    .data
                    .read_u16::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                first_edge: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                num_edges: self
                    .data
                    .read_u16::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                texinfo_index: self
                    .data
                    .read_u16::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                lightmap_offset: {
                    // Skip styles[4], then read the lightmap offset
                    self.data
                        .seek(SeekFrom::Current(4))
                        .map_err(|e| e.to_string())?;
                    self.data
                        .read_i32::<LittleEndian>()
                        .map_err(|e| e.to_string())?
                },
            });
        }

        Ok(faces)
    }

    fn parse_texinfos(&mut self, lump: &Lump) -> Result<Vec<TexInfo>, String> {
        let count = lump.length / 40;
        let mut texinfos = Vec::with_capacity(count as usize);
        self.data
            .seek(SeekFrom::Start(lump.offset as u64))
            .map_err(|e| e.to_string())?;

        for _ in 0..count {
            let mut s = [0f32; 4];
            let mut t = [0f32; 4];
            for v in s.iter_mut() {
                *v = self
                    .data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?;
            }
            for v in t.iter_mut() {
                *v = self
                    .data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?;
            }
            texinfos.push(TexInfo {
                s,
                t,
                miptex_index: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                flags: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
            });
        }

        Ok(texinfos)
    }

    fn parse_textures(&mut self, lump: &Lump) -> Result<Vec<MipTex>, String> {
        if lump.length == 0 {
            return Ok(Vec::new());
        }

        self.data
            .seek(SeekFrom::Start(lump.offset as u64))
            .map_err(|e| e.to_string())?;
        let num_textures = self
            .data
            .read_i32::<LittleEndian>()
            .map_err(|e| e.to_string())?;

        let mut offsets = Vec::with_capacity(num_textures as usize);
        for _ in 0..num_textures {
            offsets.push(
                self.data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
            );
        }

        let mut textures = Vec::with_capacity(num_textures as usize);
        for offset in offsets {
            if offset == -1 {
                textures.push(MipTex {
                    name: String::new(),
                });
                continue;
            }

            self.data
                .seek(SeekFrom::Start((lump.offset + offset) as u64))
                .map_err(|e| e.to_string())?;
            let mut name_bytes = [0u8; 16];
            self.data
                .read_exact(&mut name_bytes)
                .map_err(|e| e.to_string())?;
            let name_end = name_bytes
                .iter()
                .position(|&byte| byte == 0)
                .unwrap_or(name_bytes.len());
            let name = String::from_utf8_lossy(&name_bytes[..name_end]).to_string();
            textures.push(MipTex { name });
        }

        Ok(textures)
    }

    fn parse_models(&mut self, lump: &Lump) -> Result<Vec<Model>, String> {
        let count = lump.length / 64;
        let mut models = Vec::with_capacity(count as usize);
        self.data
            .seek(SeekFrom::Start(lump.offset as u64))
            .map_err(|e| e.to_string())?;

        for _ in 0..count {
            let mins = Vec3::new(
                self.data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                self.data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                self.data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
            );
            let maxs = Vec3::new(
                self.data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                self.data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                self.data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
            );
            // Skip origin(12) + headnodes[4](16) + visleafs(4)
            self.data
                .seek(SeekFrom::Current(32))
                .map_err(|e| e.to_string())?;
            let first_face = self
                .data
                .read_i32::<LittleEndian>()
                .map_err(|e| e.to_string())?;
            let num_faces = self
                .data
                .read_i32::<LittleEndian>()
                .map_err(|e| e.to_string())?;

            models.push(Model {
                mins,
                maxs,
                first_face,
                num_faces,
            });
        }

        Ok(models)
    }

    fn parse_entities(&mut self, lump: &Lump) -> Result<Vec<BspEntity>, String> {
        if lump.length == 0 {
            return Ok(Vec::new());
        }

        self.data
            .seek(SeekFrom::Start(lump.offset as u64))
            .map_err(|e| e.to_string())?;
        let mut text = vec![0u8; lump.length as usize];
        self.data.read_exact(&mut text).map_err(|e| e.to_string())?;
        let text = String::from_utf8_lossy(&text);

        let mut entities = Vec::new();
        let mut in_entity = false;
        let mut current_props: Vec<(String, String)> = Vec::new();

        for line in text.lines() {
            let line = line.trim();
            if line == "{" {
                in_entity = true;
                current_props.clear();
            } else if line == "}" {
                if in_entity {
                    let classname = current_props
                        .iter()
                        .find(|(k, _)| k == "classname")
                        .map(|(_, v)| v.clone())
                        .unwrap_or_default();

                    let origin =
                        current_props
                            .iter()
                            .find(|(k, _)| k == "origin")
                            .and_then(|(_, v)| {
                                let parts: Vec<f32> = v
                                    .split_whitespace()
                                    .filter_map(|s| s.parse().ok())
                                    .collect();
                                if parts.len() == 3 {
                                    Some(Vec3::new(parts[0], parts[1], parts[2]))
                                } else {
                                    None
                                }
                            });

                    entities.push(BspEntity {
                        classname,
                        origin,
                        properties: current_props.clone(),
                    });
                }
                in_entity = false;
            } else if in_entity && line.starts_with('"') {
                // Parse "key" "value"
                let parts: Vec<&str> = line.split('"').collect();
                if parts.len() >= 4 {
                    current_props.push((parts[1].to_string(), parts[3].to_string()));
                }
            }
        }

        Ok(entities)
    }

    fn build_geometry(
        &self,
        vertices: &[Vec3],
        edges: &[(u16, u16)],
        surfedges: &[i32],
        planes: &[Plane],
        faces: &[Face],
        texinfos: &[TexInfo],
        textures: &[MipTex],
        models: &[Model],
        lighting: &[u8],
    ) -> Result<(Vec<f32>, Vec<f32>, Vec<f32>, Vec3, Vec3), String> {
        let mut out_verts = Vec::new();
        let mut out_normals = Vec::new();
        let mut out_colors = Vec::new();

        let scale = 0.01f32;
        let mut bounds_min = Vec3::new(f32::MAX, f32::MAX, f32::MAX);
        let mut bounds_max = Vec3::new(f32::MIN, f32::MIN, f32::MIN);

        // Process world model (model 0)
        if let Some(world) = models.first() {
            bounds_min = Vec3::new(
                world.mins.x * scale,
                world.mins.z * scale,
                -world.maxs.y * scale,
            );
            bounds_max = Vec3::new(
                world.maxs.x * scale,
                world.maxs.z * scale,
                -world.mins.y * scale,
            );

            for model in models {
                self.process_model_faces(
                    model,
                    vertices,
                    edges,
                    surfedges,
                    planes,
                    faces,
                    texinfos,
                    textures,
                    lighting,
                    scale,
                    &mut out_verts,
                    &mut out_normals,
                    &mut out_colors,
                );
            }
        }

        Ok((out_verts, out_normals, out_colors, bounds_min, bounds_max))
    }

    fn process_model_faces(
        &self,
        model: &Model,
        vertices: &[Vec3],
        edges: &[(u16, u16)],
        surfedges: &[i32],
        planes: &[Plane],
        faces: &[Face],
        texinfos: &[TexInfo],
        textures: &[MipTex],
        lighting: &[u8],
        scale: f32,
        out_verts: &mut Vec<f32>,
        out_normals: &mut Vec<f32>,
        out_colors: &mut Vec<f32>,
    ) {
        for i in 0..model.num_faces {
            let face_idx = (model.first_face + i) as usize;
            if face_idx >= faces.len() {
                continue;
            }
            let face = &faces[face_idx];

            // Get texture info
            let texinfo = texinfos.get(face.texinfo_index as usize);
            if let Some(ti) = texinfo {
                if ti.flags != 0 {
                    continue; // Skip special surfaces
                }
            }

            // Get texture name
            let tex_name = texinfo
                .and_then(|ti| textures.get(ti.miptex_index as usize))
                .map(|t| t.name.as_str())
                .unwrap_or("");

            // Skip sky/clip/trigger textures
            let name_lower = tex_name.to_lowercase();
            if name_lower.starts_with("sky")
                || name_lower == "aaatrigger"
                || name_lower == "clip"
                || name_lower.starts_with("null")
            {
                continue;
            }

            // Get color for texture
            let (r, g, b) = texture_color(&name_lower);

            // Get face vertices
            let mut face_verts = Vec::new();
            for j in 0..face.num_edges {
                let se_idx = (face.first_edge + j as i32) as usize;
                if se_idx >= surfedges.len() {
                    continue;
                }
                let edge_idx = surfedges[se_idx];
                let edge = edges.get(edge_idx.unsigned_abs() as usize);
                if let Some(&(v0, v1)) = edge {
                    let vi = if edge_idx >= 0 { v0 } else { v1 } as usize;
                    if let Some(v) = vertices.get(vi) {
                        face_verts.push(v.clone());
                    }
                }
            }

            if face_verts.len() < 3 {
                continue;
            }

            // Get normal
            let plane = planes.get(face.plane_index as usize);
            let (mut nx, mut ny, mut nz) = plane
                .map(|p| (p.normal.x, p.normal.z, -p.normal.y))
                .unwrap_or((0.0, 1.0, 0.0));

            if face.plane_side != 0 {
                nx = -nx;
                ny = -ny;
                nz = -nz;
            }

            // Per-vertex lightmap sample: project each vertex into the face's
            // lightmap (16-unit luxel grid over the texture-space extents).
            let lit: Vec<(f32, f32, f32)> = if let (Some(ti), true) =
                (texinfo, face.lightmap_offset >= 0 && !lighting.is_empty())
            {
                let uv: Vec<(f32, f32)> = face_verts
                    .iter()
                    .map(|v| {
                        (
                            v.x * ti.s[0] + v.y * ti.s[1] + v.z * ti.s[2] + ti.s[3],
                            v.x * ti.t[0] + v.y * ti.t[1] + v.z * ti.t[2] + ti.t[3],
                        )
                    })
                    .collect();
                let (mut min_u, mut max_u, mut min_v, mut max_v) =
                    (f32::MAX, f32::MIN, f32::MAX, f32::MIN);
                for &(u, v) in &uv {
                    min_u = min_u.min(u);
                    max_u = max_u.max(u);
                    min_v = min_v.min(v);
                    max_v = max_v.max(v);
                }
                let bmin_u = (min_u / 16.0).floor();
                let bmin_v = (min_v / 16.0).floor();
                let w = ((max_u / 16.0).ceil() - bmin_u) as i32 + 1;
                let h = ((max_v / 16.0).ceil() - bmin_v) as i32 + 1;
                uv.iter()
                    .map(|&(u, v)| {
                        let lx = ((u / 16.0 - bmin_u) as i32).clamp(0, w - 1);
                        let ly = ((v / 16.0 - bmin_v) as i32).clamp(0, h - 1);
                        let idx = face.lightmap_offset as usize + ((ly * w + lx) as usize) * 3;
                        if idx + 2 < lighting.len() {
                            // Overbright scale ~2 like the engine, clamped
                            let lr = (lighting[idx] as f32 / 255.0 * 2.0).min(1.5);
                            let lg = (lighting[idx + 1] as f32 / 255.0 * 2.0).min(1.5);
                            let lb = (lighting[idx + 2] as f32 / 255.0 * 2.0).min(1.5);
                            ((r * lr).min(1.0), (g * lg).min(1.0), (b * lb).min(1.0))
                        } else {
                            (r * 0.85, g * 0.85, b * 0.85)
                        }
                    })
                    .collect()
            } else {
                vec![(r * 0.85, g * 0.85, b * 0.85); face_verts.len()]
            };

            // Triangulate (fan)
            for j in 1..face_verts.len() - 1 {
                for &k in &[0, j, j + 1] {
                    let v = &face_verts[k];
                    out_verts.extend_from_slice(&[v.x * scale, v.z * scale, -v.y * scale]);
                    out_normals.extend_from_slice(&[nx, ny, nz]);
                    let (cr, cg, cb) = lit[k];
                    out_colors.extend_from_slice(&[cr, cg, cb]);
                }
            }
        }
    }
}

fn texture_color(name: &str) -> (f32, f32, f32) {
    if name.contains("concrete") || name.contains("cement") {
        return (0.5, 0.5, 0.5);
    }
    if name.contains("brick") {
        return (0.55, 0.27, 0.07);
    }
    if name.contains("metal") {
        return (0.44, 0.44, 0.5);
    }
    if name.contains("wood") {
        return (0.55, 0.45, 0.33);
    }
    if name.contains("sand") || name.contains("dust") {
        return (0.76, 0.7, 0.5);
    }
    if name.contains("grass") {
        return (0.34, 0.49, 0.27);
    }
    if name.contains("tile") {
        return (0.69, 0.69, 0.69);
    }
    if name.contains("water") {
        return (0.25, 0.41, 0.88);
    }

    // Hash-based color for variety
    let hash: u32 = name
        .bytes()
        .fold(0u32, |acc, b| acc.wrapping_add(b as u32).wrapping_mul(31));
    let hue = (hash % 360) as f32 / 360.0;

    // HSL to RGB (simplified, s=0.3, l=0.5)
    let c = 0.3f32;
    let x = c * (1.0 - ((hue * 6.0) % 2.0 - 1.0).abs());
    let m = 0.35f32;

    let (r, g, b) = match (hue * 6.0) as u32 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };

    (r + m, g + m, b + m)
}

impl<'a> BspParser<'a> {
    /// Textured parse: same BSP walk, but emits per-texture geometry groups
    /// with UVs and RGBA pixels (embedded miptex or from supplied WADs).
    pub fn parse_textured(
        &mut self,
        wads: &std::collections::HashMap<String, (u32, u32, Vec<u8>)>,
    ) -> Result<TexturedBsp, String> {
        self.data
            .seek(SeekFrom::Start(0))
            .map_err(|e| e.to_string())?;
        let version = self
            .data
            .read_i32::<LittleEndian>()
            .map_err(|e| e.to_string())?;
        if version != 30 {
            return Err(format!("Unsupported BSP version: {}", version));
        }
        let mut lumps = Vec::with_capacity(LUMP_COUNT);
        for _ in 0..LUMP_COUNT {
            lumps.push(Lump {
                offset: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                length: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
            });
        }

        let vertices = self.parse_vertices(&lumps[LUMP_VERTICES])?;
        let edges = self.parse_edges(&lumps[LUMP_EDGES])?;
        let surfedges = self.parse_surfedges(&lumps[LUMP_SURFEDGES])?;
        let planes = self.parse_planes(&lumps[LUMP_PLANES])?;
        let faces = self.parse_faces(&lumps[LUMP_FACES])?;
        let texinfos = self.parse_texinfos(&lumps[LUMP_TEXINFO])?;
        let models = self.parse_models(&lumps[LUMP_MODELS])?;
        let entities = self.parse_entities(&lumps[LUMP_ENTITIES])?;
        let lighting = self.read_raw_lump(&lumps[LUMP_LIGHTING])?;
        let tex_lump = self.read_raw_lump(&lumps[LUMP_TEXTURES])?;

        // Decode all miptexes: embedded pixels, or resolved from WADs
        let mut mips: Vec<(String, u32, u32, Option<Vec<u8>>)> = Vec::new();
        if tex_lump.len() >= 4 {
            let n = i32::from_le_bytes(tex_lump[0..4].try_into().unwrap()) as usize;
            for i in 0..n.min(4096) {
                let o = 4 + i * 4;
                if o + 4 > tex_lump.len() {
                    break;
                }
                let off = i32::from_le_bytes(tex_lump[o..o + 4].try_into().unwrap());
                if off < 0 || off as usize >= tex_lump.len() {
                    mips.push((String::new(), 0, 0, None));
                    continue;
                }
                match decode_miptex(&tex_lump[off as usize..]) {
                    Some((name, w, h, pixels)) => {
                        let pixels = pixels
                            .or_else(|| wads.get(&name.to_lowercase()).map(|(_, _, p)| p.clone()));
                        mips.push((name, w, h, pixels));
                    }
                    None => mips.push((String::new(), 0, 0, None)),
                }
            }
        }

        // Bucket triangles per miptex index
        let scale = 0.01f32;
        struct Bucket {
            positions: Vec<f32>,
            normals: Vec<f32>,
            colors: Vec<f32>,
            uvs: Vec<f32>,
        }
        // Keep brush submodels separate from the world. A texture-only bucket
        // baked doors, trains, and fans permanently into model 0, making it
        // impossible for the renderer to replay their entity transforms.
        let mut buckets: std::collections::BTreeMap<(usize, usize), Bucket> = Default::default();

        for (model_index, model) in models.iter().enumerate() {
            for i in 0..model.num_faces {
                let face_idx = (model.first_face + i) as usize;
                let Some(face) = faces.get(face_idx) else {
                    continue;
                };
                let Some(ti) = texinfos.get(face.texinfo_index as usize) else {
                    continue;
                };
                if ti.flags != 0 {
                    continue;
                }
                let mip_idx = ti.miptex_index.max(0) as usize;
                let (tex_name, tw, th) = mips
                    .get(mip_idx)
                    .map(|(n, w, h, _)| (n.as_str(), *w, *h))
                    .unwrap_or(("", 0, 0));
                let name_lower = tex_name.to_lowercase();
                if name_lower.starts_with("sky")
                    || name_lower == "aaatrigger"
                    || name_lower == "clip"
                    || name_lower.starts_with("null")
                {
                    continue;
                }
                let (r, g, b) = texture_color(&name_lower);

                let mut face_verts: Vec<Vec3> = Vec::new();
                for j in 0..face.num_edges {
                    let se_idx = (face.first_edge + j as i32) as usize;
                    let Some(&edge_idx) = surfedges.get(se_idx) else {
                        continue;
                    };
                    let Some(&(v0, v1)) = edges.get(edge_idx.unsigned_abs() as usize) else {
                        continue;
                    };
                    let vi = if edge_idx >= 0 { v0 } else { v1 } as usize;
                    if let Some(v) = vertices.get(vi) {
                        face_verts.push(v.clone());
                    }
                }
                if face_verts.len() < 3 {
                    continue;
                }

                let plane = planes.get(face.plane_index as usize);
                let (mut nx, mut ny, mut nz) = plane
                    .map(|p| (p.normal.x, p.normal.z, -p.normal.y))
                    .unwrap_or((0.0, 1.0, 0.0));
                if face.plane_side != 0 {
                    nx = -nx;
                    ny = -ny;
                    nz = -nz;
                }

                // Texture-space UV per vertex (repeat wrapping handles tiling)
                let uv: Vec<(f32, f32)> = face_verts
                    .iter()
                    .map(|v| {
                        (
                            v.x * ti.s[0] + v.y * ti.s[1] + v.z * ti.s[2] + ti.s[3],
                            v.x * ti.t[0] + v.y * ti.t[1] + v.z * ti.t[2] + ti.t[3],
                        )
                    })
                    .collect();

                // Lightmap sample (same math as untextured path)
                let lit: Vec<(f32, f32, f32)> = if face.lightmap_offset >= 0 && !lighting.is_empty()
                {
                    let (mut min_u, mut max_u, mut min_v, mut max_v) =
                        (f32::MAX, f32::MIN, f32::MAX, f32::MIN);
                    for &(u, v) in &uv {
                        min_u = min_u.min(u);
                        max_u = max_u.max(u);
                        min_v = min_v.min(v);
                        max_v = max_v.max(v);
                    }
                    let bmin_u = (min_u / 16.0).floor();
                    let bmin_v = (min_v / 16.0).floor();
                    let w = ((max_u / 16.0).ceil() - bmin_u) as i32 + 1;
                    let h = ((max_v / 16.0).ceil() - bmin_v) as i32 + 1;
                    uv.iter()
                        .map(|&(u, v)| {
                            let lx = ((u / 16.0 - bmin_u) as i32).clamp(0, w - 1);
                            let ly = ((v / 16.0 - bmin_v) as i32).clamp(0, h - 1);
                            let idx = face.lightmap_offset as usize + ((ly * w + lx) as usize) * 3;
                            if idx + 2 < lighting.len() {
                                let lr = (lighting[idx] as f32 / 255.0 * 2.0).min(1.5);
                                let lg = (lighting[idx + 1] as f32 / 255.0 * 2.0).min(1.5);
                                let lb = (lighting[idx + 2] as f32 / 255.0 * 2.0).min(1.5);
                                (lr.min(1.0), lg.min(1.0), lb.min(1.0))
                            } else {
                                (0.85, 0.85, 0.85)
                            }
                        })
                        .collect()
                } else {
                    vec![(0.85, 0.85, 0.85); face_verts.len()]
                };

                let bucket = buckets.entry((model_index, mip_idx)).or_insert_with(|| Bucket {
                    positions: Vec::new(),
                    normals: Vec::new(),
                    colors: Vec::new(),
                    uvs: Vec::new(),
                });
                let has_tex = mips.get(mip_idx).map(|m| m.3.is_some()).unwrap_or(false);
                for j in 1..face_verts.len() - 1 {
                    for &k in &[0, j, j + 1] {
                        let v = &face_verts[k];
                        bucket.positions.extend_from_slice(&[
                            v.x * scale,
                            v.z * scale,
                            -v.y * scale,
                        ]);
                        bucket.normals.extend_from_slice(&[nx, ny, nz]);
                        let (lr, lg, lb) = lit[k];
                        // With a texture, vertex color is pure light; without, tint by texture_color
                        if has_tex {
                            bucket.colors.extend_from_slice(&[lr, lg, lb]);
                        } else {
                            bucket.colors.extend_from_slice(&[r * lr, g * lg, b * lb]);
                        }
                        let (u, v2) = uv[k];
                        if tw > 0 && th > 0 {
                            bucket
                                .uvs
                                .extend_from_slice(&[u / tw as f32, v2 / th as f32]);
                        } else {
                            bucket.uvs.extend_from_slice(&[0.0, 0.0]);
                        }
                    }
                }
            }
        }

        // Flatten buckets into contiguous arrays + groups
        let mut out = TexturedBsp {
            groups: Vec::new(),
            positions: Vec::new(),
            normals: Vec::new(),
            colors: Vec::new(),
            uvs: Vec::new(),
            pixels: Vec::new(),
            entities,
            bounds_min: Vec3::new(0.0, 0.0, 0.0),
            bounds_max: Vec3::new(0.0, 0.0, 0.0),
        };
        if let Some(world) = models.first() {
            out.bounds_min = Vec3::new(
                world.mins.x * scale,
                world.mins.z * scale,
                -world.maxs.y * scale,
            );
            out.bounds_max = Vec3::new(
                world.maxs.x * scale,
                world.maxs.z * scale,
                -world.mins.y * scale,
            );
        }
        let mut pix_offset_of: std::collections::HashMap<usize, i64> = Default::default();
        for ((model_index, mip_idx), bucket) in buckets {
            let (name, w, h, pixels) =
                mips.get(mip_idx)
                    .cloned()
                    .unwrap_or((String::new(), 0, 0, None));
            let pix_offset = if let Some(p) = pixels {
                *pix_offset_of.entry(mip_idx).or_insert_with(|| {
                    let off = out.pixels.len() as i64;
                    out.pixels.extend_from_slice(&p);
                    off
                })
            } else {
                -1
            };
            let vert_start = (out.positions.len() / 3) as u32;
            let vert_count = (bucket.positions.len() / 3) as u32;
            out.positions.extend_from_slice(&bucket.positions);
            out.normals.extend_from_slice(&bucket.normals);
            out.colors.extend_from_slice(&bucket.colors);
            out.uvs.extend_from_slice(&bucket.uvs);
            out.groups.push(TexGroup {
                model_index: model_index as u32,
                name,
                width: w,
                height: h,
                vert_start,
                vert_count,
                pix_offset,
            });
        }
        Ok(out)
    }
}

// === Textured pipeline ===

pub struct TexGroup {
    pub model_index: u32,
    pub name: String,
    pub width: u32,
    pub height: u32,
    pub vert_start: u32,
    pub vert_count: u32,
    pub pix_offset: i64, // -1 = no pixels (flat color fallback)
}

pub struct TexturedBsp {
    pub groups: Vec<TexGroup>,
    pub positions: Vec<f32>,
    pub normals: Vec<f32>,
    pub colors: Vec<f32>,
    pub uvs: Vec<f32>,
    pub pixels: Vec<u8>, // concatenated RGBA blocks addressed by pix_offset
    pub entities: Vec<BspEntity>,
    pub bounds_min: Vec3,
    pub bounds_max: Vec3,
}

/// Decode a miptex (BSP-embedded or WAD lump) into RGBA. `data` starts at the
/// miptex header. Returns None if the texture is external (mip offset 0).
fn decode_miptex(data: &[u8]) -> Option<(String, u32, u32, Option<Vec<u8>>)> {
    if data.len() < 40 {
        return None;
    }
    // External miptex headers in some official maps contain uninitialized bytes
    // after the first NUL. Treat the field as a C string instead of only trimming
    // trailing NULs, otherwise WAD lookup receives a corrupted texture name.
    let name_end = data[0..16].iter().position(|&byte| byte == 0).unwrap_or(16);
    let name = String::from_utf8_lossy(&data[..name_end]).to_string();
    let w = u32::from_le_bytes(data[16..20].try_into().ok()?);
    let h = u32::from_le_bytes(data[20..24].try_into().ok()?);
    if w == 0 || h == 0 || w > 1024 || h > 1024 {
        return None;
    }
    let mip0 = u32::from_le_bytes(data[24..28].try_into().ok()?) as usize;
    if mip0 == 0 {
        return Some((name, w, h, None)); // external reference
    }
    let (w_us, h_us) = (w as usize, h as usize);
    let pix_end = mip0 + w_us * h_us;
    // Palette follows the 4 mip levels + a 2-byte count
    let pal_off = mip0
        + w_us * h_us
        + (w_us / 2) * (h_us / 2)
        + (w_us / 4) * (h_us / 4)
        + (w_us / 8) * (h_us / 8)
        + 2;
    if pix_end > data.len() || pal_off + 256 * 3 > data.len() {
        return Some((name, w, h, None));
    }
    let palette = &data[pal_off..pal_off + 256 * 3];
    let transparent = name.starts_with('{');
    let mut rgba = Vec::with_capacity(w_us * h_us * 4);
    for &idx in &data[mip0..pix_end] {
        let i = idx as usize * 3;
        if transparent && idx == 255 {
            rgba.extend_from_slice(&[0, 0, 0, 0]);
        } else {
            rgba.extend_from_slice(&[palette[i], palette[i + 1], palette[i + 2], 255]);
        }
    }
    Some((name, w, h, Some(rgba)))
}

/// Parse a WAD3 file, adding miptex entries to `out` (keyed lowercase).
pub fn parse_wad(data: &[u8], out: &mut std::collections::HashMap<String, (u32, u32, Vec<u8>)>) {
    if data.len() < 12 || &data[0..4] != b"WAD3" {
        return;
    }
    let num = i32::from_le_bytes(data[4..8].try_into().unwrap()) as usize;
    let dir = i32::from_le_bytes(data[8..12].try_into().unwrap()) as usize;
    for i in 0..num {
        let e = dir + i * 32;
        if e + 32 > data.len() {
            break;
        }
        let filepos = i32::from_le_bytes(data[e..e + 4].try_into().unwrap()) as usize;
        let entry_type = data[e + 12];
        if entry_type != 0x43 || filepos >= data.len() {
            continue; // only miptex lumps
        }
        if let Some((name, w, h, Some(rgba))) = decode_miptex(&data[filepos..]) {
            out.entry(name.to_lowercase()).or_insert((w, h, rgba));
        }
    }
}
