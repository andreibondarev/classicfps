import {
  BSPHeader,
  BSPLump,
  BSPPlane,
  BSPVertex,
  BSPEdge,
  BSPFace,
  BSPTexInfo,
  BSPMipTex,
  BSPModel,
  BSPEntity,
  ParsedBSP,
  Vec3,
  LUMP,
  LUMP_COUNT,
} from './types.ts';

export class BSPParser {
  private data: DataView;
  private buffer: Uint8Array;
  private offset: number = 0;

  constructor(arrayBuffer: ArrayBuffer) {
    this.buffer = new Uint8Array(arrayBuffer);
    this.data = new DataView(arrayBuffer);
  }

  parse(): ParsedBSP {
    const header = this.parseHeader();

    // Validate BSP version (should be 30 for GoldSrc)
    if (header.version !== 30) {
      console.warn(`Unexpected BSP version: ${header.version}, expected 30`);
    }

    const entities = this.parseEntities(header.lumps[LUMP.ENTITIES]);
    const planes = this.parsePlanes(header.lumps[LUMP.PLANES]);
    const vertices = this.parseVertices(header.lumps[LUMP.VERTICES]);
    const edges = this.parseEdges(header.lumps[LUMP.EDGES]);
    const surfEdges = this.parseSurfEdges(header.lumps[LUMP.SURFEDGES]);
    const faces = this.parseFaces(header.lumps[LUMP.FACES]);
    const texInfos = this.parseTexInfos(header.lumps[LUMP.TEXINFO]);
    const textures = this.parseTextures(header.lumps[LUMP.TEXTURES]);
    const models = this.parseModels(header.lumps[LUMP.MODELS]);
    const lightmapData = this.parseLightmap(header.lumps[LUMP.LIGHTING]);

    return {
      header,
      entities,
      planes,
      vertices,
      edges,
      surfEdges,
      faces,
      texInfos,
      textures,
      models,
      lightmapData,
    };
  }

  private parseHeader(): BSPHeader {
    this.offset = 0;
    const version = this.readInt32();
    const lumps: BSPLump[] = [];

    for (let i = 0; i < LUMP_COUNT; i++) {
      lumps.push({
        offset: this.readInt32(),
        length: this.readInt32(),
      });
    }

    return { version, lumps };
  }

  private parseEntities(lump: BSPLump): BSPEntity[] {
    if (lump.length === 0) return [];

    this.offset = lump.offset;
    const text = this.readString(lump.length).replace(/\0/g, '');
    const entities: BSPEntity[] = [];

    // Parse entity text format: { "key" "value" ... }
    const entityRegex = /\{([^}]+)\}/g;
    let match;

    while ((match = entityRegex.exec(text)) !== null) {
      const entityText = match[1];
      const properties: Record<string, string> = {};

      const propRegex = /"([^"]+)"\s+"([^"]*)"/g;
      let propMatch;

      while ((propMatch = propRegex.exec(entityText)) !== null) {
        properties[propMatch[1]] = propMatch[2];
      }

      if (properties.classname) {
        entities.push({
          classname: properties.classname,
          properties,
        });
      }
    }

    return entities;
  }

  private parsePlanes(lump: BSPLump): BSPPlane[] {
    const count = lump.length / 20; // Each plane is 20 bytes
    const planes: BSPPlane[] = [];
    this.offset = lump.offset;

    for (let i = 0; i < count; i++) {
      planes.push({
        normal: this.readVec3(),
        dist: this.readFloat32(),
        type: this.readInt32(),
      });
    }

    return planes;
  }

  private parseVertices(lump: BSPLump): BSPVertex[] {
    const count = lump.length / 12; // Each vertex is 12 bytes (3 floats)
    const vertices: BSPVertex[] = [];
    this.offset = lump.offset;

    for (let i = 0; i < count; i++) {
      vertices.push({
        x: this.readFloat32(),
        y: this.readFloat32(),
        z: this.readFloat32(),
      });
    }

    return vertices;
  }

  private parseEdges(lump: BSPLump): BSPEdge[] {
    const count = lump.length / 4; // Each edge is 4 bytes (2 uint16)
    const edges: BSPEdge[] = [];
    this.offset = lump.offset;

    for (let i = 0; i < count; i++) {
      edges.push({
        v0: this.readUint16(),
        v1: this.readUint16(),
      });
    }

    return edges;
  }

  private parseSurfEdges(lump: BSPLump): number[] {
    const count = lump.length / 4; // Each surfedge is a signed int32
    const surfEdges: number[] = [];
    this.offset = lump.offset;

    for (let i = 0; i < count; i++) {
      surfEdges.push(this.readInt32());
    }

    return surfEdges;
  }

  private parseFaces(lump: BSPLump): BSPFace[] {
    const count = lump.length / 20; // Each face is 20 bytes
    const faces: BSPFace[] = [];
    this.offset = lump.offset;

    for (let i = 0; i < count; i++) {
      faces.push({
        planeIndex: this.readUint16(),
        planeSide: this.readUint16(),
        firstEdge: this.readInt32(),
        numEdges: this.readUint16(),
        texinfoIndex: this.readUint16(),
        styles: [
          this.readUint8(),
          this.readUint8(),
          this.readUint8(),
          this.readUint8(),
        ],
        lightmapOffset: this.readInt32(),
      });
    }

    return faces;
  }

  private parseTexInfos(lump: BSPLump): BSPTexInfo[] {
    const count = lump.length / 40; // Each texinfo is 40 bytes
    const texInfos: BSPTexInfo[] = [];
    this.offset = lump.offset;

    for (let i = 0; i < count; i++) {
      texInfos.push({
        sVector: this.readVec3(),
        sShift: this.readFloat32(),
        tVector: this.readVec3(),
        tShift: this.readFloat32(),
        miptexIndex: this.readInt32(),
        flags: this.readInt32(),
      });
    }

    return texInfos;
  }

  private parseTextures(lump: BSPLump): BSPMipTex[] {
    if (lump.length === 0) return [];

    this.offset = lump.offset;
    const numTextures = this.readInt32();
    const offsets: number[] = [];

    for (let i = 0; i < numTextures; i++) {
      offsets.push(this.readInt32());
    }

    const textures: BSPMipTex[] = [];

    for (let i = 0; i < numTextures; i++) {
      if (offsets[i] === -1) {
        // External texture, not embedded
        textures.push({
          name: '',
          width: 0,
          height: 0,
          offsets: [0, 0, 0, 0],
        });
        continue;
      }

      this.offset = lump.offset + offsets[i];
      const name = this.readString(16).replace(/\0.*$/, '');
      const width = this.readUint32();
      const height = this.readUint32();
      const mipOffsets: [number, number, number, number] = [
        this.readUint32(),
        this.readUint32(),
        this.readUint32(),
        this.readUint32(),
      ];

      textures.push({
        name,
        width,
        height,
        offsets: mipOffsets,
      });
    }

    return textures;
  }

  private parseModels(lump: BSPLump): BSPModel[] {
    const count = lump.length / 64; // Each model is 64 bytes
    const models: BSPModel[] = [];
    this.offset = lump.offset;

    for (let i = 0; i < count; i++) {
      models.push({
        mins: this.readVec3(),
        maxs: this.readVec3(),
        origin: this.readVec3(),
        headNodes: [
          this.readInt32(),
          this.readInt32(),
          this.readInt32(),
          this.readInt32(),
        ],
        visLeaves: this.readInt32(),
        firstFace: this.readInt32(),
        numFaces: this.readInt32(),
      });
    }

    return models;
  }

  private parseLightmap(lump: BSPLump): Uint8Array {
    if (lump.length === 0) return new Uint8Array(0);
    return this.buffer.slice(lump.offset, lump.offset + lump.length);
  }

  // Utility reading methods
  private readVec3(): Vec3 {
    return {
      x: this.readFloat32(),
      y: this.readFloat32(),
      z: this.readFloat32(),
    };
  }

  private readUint8(): number {
    const value = this.data.getUint8(this.offset);
    this.offset += 1;
    return value;
  }

  private readUint16(): number {
    const value = this.data.getUint16(this.offset, true);
    this.offset += 2;
    return value;
  }

  private readInt32(): number {
    const value = this.data.getInt32(this.offset, true);
    this.offset += 4;
    return value;
  }

  private readUint32(): number {
    const value = this.data.getUint32(this.offset, true);
    this.offset += 4;
    return value;
  }

  private readFloat32(): number {
    const value = this.data.getFloat32(this.offset, true);
    this.offset += 4;
    return value;
  }

  private readString(length: number): string {
    const bytes = this.buffer.slice(this.offset, this.offset + length);
    this.offset += length;
    return new TextDecoder('latin1').decode(bytes);
  }
}
