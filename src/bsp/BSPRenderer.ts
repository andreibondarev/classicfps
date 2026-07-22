import * as THREE from 'three';
import { ParsedBSP, BSPFace, BSPVertex } from './types.ts';

// Texture categories for coloring
const TEXTURE_COLORS: Record<string, number> = {
  // Sky
  'sky': 0x87ceeb,
  // Common CS textures
  'concrete': 0x808080,
  'brick': 0x8b4513,
  'metal': 0x707080,
  'wood': 0x8b7355,
  'sand': 0xc2b280,
  'dirt': 0x8b7355,
  'grass': 0x567d46,
  'tile': 0xb0b0b0,
  'stone': 0x696969,
  'water': 0x4169e1,
  'glass': 0xadd8e6,
  // Default
  'default': 0x606060,
};

function getTextureColor(textureName: string): number {
  const name = textureName.toLowerCase();

  // Check for sky textures (should be invisible/sky color)
  if (name.startsWith('sky') || name === 'aaatrigger' || name === 'clip') {
    return TEXTURE_COLORS.sky;
  }

  // Match texture name to color category
  for (const [key, color] of Object.entries(TEXTURE_COLORS)) {
    if (name.includes(key)) {
      return color;
    }
  }

  // Color based on first character for variety
  const hash = name.charCodeAt(0) + (name.charCodeAt(1) || 0) * 256;
  const hue = (hash % 360) / 360;
  const color = new THREE.Color();
  color.setHSL(hue, 0.3, 0.5);
  return color.getHex();
}

export class BSPRenderer {
  private bsp: ParsedBSP;
  private scale: number;
  private group: THREE.Group;

  // Same scale as player renderer
  private readonly SCALE = 0.01;

  constructor(bsp: ParsedBSP) {
    this.bsp = bsp;
    this.scale = this.SCALE;
    this.group = new THREE.Group();
  }

  createMesh(): THREE.Group {
    // Collect ALL vertices and colors into single arrays for one draw call
    const allVertices: number[] = [];
    const allNormals: number[] = [];
    const allColors: number[] = [];

    // Process world model (model 0 is always the world)
    if (this.bsp.models.length > 0) {
      const worldModel = this.bsp.models[0];
      this.collectFaces(worldModel.firstFace, worldModel.numFaces, allVertices, allNormals, allColors);
    }

    // Also render brush entities (doors, etc.) - models 1+
    for (let i = 1; i < this.bsp.models.length; i++) {
      const model = this.bsp.models[i];
      this.collectFaces(model.firstFace, model.numFaces, allVertices, allNormals, allColors, model.origin);
    }

    // Create single merged geometry
    if (allVertices.length > 0) {
      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute('position', new THREE.Float32BufferAttribute(allVertices, 3));
      geometry.setAttribute('normal', new THREE.Float32BufferAttribute(allNormals, 3));
      geometry.setAttribute('color', new THREE.Float32BufferAttribute(allColors, 3));

      const material = new THREE.MeshStandardMaterial({
        vertexColors: true,
        roughness: 0.8,
        metalness: 0.1,
        side: THREE.DoubleSide,
        flatShading: true,
      });

      const mesh = new THREE.Mesh(geometry, material);
      this.group.add(mesh);

      console.log(`BSP: Single mesh with ${allVertices.length / 3} vertices`);
    }

    return this.group;
  }

  private collectFaces(
    firstFace: number,
    numFaces: number,
    vertices: number[],
    normals: number[],
    colors: number[],
    origin?: { x: number; y: number; z: number }
  ): void {
    const ox = (origin?.x ?? 0) * this.scale;
    const oy = (origin?.z ?? 0) * this.scale;
    const oz = -(origin?.y ?? 0) * this.scale;

    for (let i = 0; i < numFaces; i++) {
      const face = this.bsp.faces[firstFace + i];
      const texInfo = this.bsp.texInfos[face.texinfoIndex];

      // Skip special textures
      if (texInfo && texInfo.flags !== 0) continue;

      // Get texture name for coloring
      let textureName = 'default';
      const texIndex = texInfo?.miptexIndex ?? -1;
      if (texIndex >= 0 && texIndex < this.bsp.textures.length) {
        textureName = this.bsp.textures[texIndex].name || 'default';
      }

      // Skip sky and trigger textures
      const nameLower = textureName.toLowerCase();
      if (nameLower.startsWith('sky') || nameLower === 'aaatrigger' ||
          nameLower === 'clip' || nameLower.startsWith('null')) {
        continue;
      }

      const color = new THREE.Color(getTextureColor(textureName));
      const faceVerts = this.getFaceVertices(face);
      if (faceVerts.length < 3) continue;

      // Get face normal
      const plane = this.bsp.planes[face.planeIndex];
      let nx = plane.normal.x;
      let ny = plane.normal.z;
      let nz = -plane.normal.y;
      if (face.planeSide !== 0) {
        nx = -nx; ny = -ny; nz = -nz;
      }

      // Triangulate and add to arrays
      for (let j = 1; j < faceVerts.length - 1; j++) {
        const v0 = faceVerts[0];
        const v1 = faceVerts[j];
        const v2 = faceVerts[j + 1];

        vertices.push(
          v0.x * this.scale + ox, v0.z * this.scale + oy, -v0.y * this.scale + oz,
          v1.x * this.scale + ox, v1.z * this.scale + oy, -v1.y * this.scale + oz,
          v2.x * this.scale + ox, v2.z * this.scale + oy, -v2.y * this.scale + oz
        );

        normals.push(nx, ny, nz, nx, ny, nz, nx, ny, nz);
        colors.push(color.r, color.g, color.b, color.r, color.g, color.b, color.r, color.g, color.b);
      }
    }
  }

  private getFaceVertices(face: BSPFace): BSPVertex[] {
    const vertices: BSPVertex[] = [];

    for (let i = 0; i < face.numEdges; i++) {
      const surfEdgeIndex = face.firstEdge + i;
      if (surfEdgeIndex >= this.bsp.surfEdges.length) continue;

      const edgeIndex = this.bsp.surfEdges[surfEdgeIndex];
      const edge = this.bsp.edges[Math.abs(edgeIndex)];
      if (!edge) continue;

      // If surfedge is negative, use second vertex; if positive, use first
      const vertexIndex = edgeIndex >= 0 ? edge.v0 : edge.v1;
      const vertex = this.bsp.vertices[vertexIndex];
      if (vertex) {
        vertices.push(vertex);
      }
    }

    return vertices;
  }

  // Get spawn points for camera positioning
  getSpawnPoints(): THREE.Vector3[] {
    const spawns: THREE.Vector3[] = [];

    for (const entity of this.bsp.entities) {
      if (entity.classname === 'info_player_start' ||
          entity.classname === 'info_player_deathmatch' ||
          entity.classname === 'info_player_terrorist' ||
          entity.classname === 'info_player_counterterrorist') {

        const origin = entity.properties.origin;
        if (origin) {
          const [x, y, z] = origin.split(' ').map(Number);
          spawns.push(new THREE.Vector3(
            x * this.scale,
            z * this.scale,
            -y * this.scale
          ));
        }
      }
    }

    return spawns;
  }

  // Get map bounds
  getBounds(): { min: THREE.Vector3; max: THREE.Vector3 } {
    if (this.bsp.models.length === 0) {
      return {
        min: new THREE.Vector3(-100, -100, -100),
        max: new THREE.Vector3(100, 100, 100),
      };
    }

    const world = this.bsp.models[0];
    return {
      min: new THREE.Vector3(
        world.mins.x * this.scale,
        world.mins.z * this.scale,
        -world.maxs.y * this.scale
      ),
      max: new THREE.Vector3(
        world.maxs.x * this.scale,
        world.maxs.z * this.scale,
        -world.mins.y * this.scale
      ),
    };
  }
}
