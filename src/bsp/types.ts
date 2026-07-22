// GoldSrc BSP format (version 30) types

export interface BSPHeader {
  version: number;
  lumps: BSPLump[];
}

export interface BSPLump {
  offset: number;
  length: number;
}

// Lump indices
export const LUMP = {
  ENTITIES: 0,
  PLANES: 1,
  TEXTURES: 2,
  VERTICES: 3,
  VISIBILITY: 4,
  NODES: 5,
  TEXINFO: 6,
  FACES: 7,
  LIGHTING: 8,
  CLIPNODES: 9,
  LEAVES: 10,
  MARKSURFACES: 11,
  EDGES: 12,
  SURFEDGES: 13,
  MODELS: 14,
} as const;

export const LUMP_COUNT = 15;

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

export interface BSPPlane {
  normal: Vec3;
  dist: number;
  type: number;
}

export interface BSPVertex {
  x: number;
  y: number;
  z: number;
}

export interface BSPEdge {
  v0: number; // Vertex indices
  v1: number;
}

export interface BSPFace {
  planeIndex: number;
  planeSide: number;
  firstEdge: number;
  numEdges: number;
  texinfoIndex: number;
  styles: [number, number, number, number];
  lightmapOffset: number;
}

export interface BSPTexInfo {
  sVector: Vec3;
  sShift: number;
  tVector: Vec3;
  tShift: number;
  miptexIndex: number;
  flags: number;
}

export interface BSPMipTex {
  name: string;
  width: number;
  height: number;
  offsets: [number, number, number, number]; // 4 mip levels
}

export interface BSPModel {
  mins: Vec3;
  maxs: Vec3;
  origin: Vec3;
  headNodes: [number, number, number, number];
  visLeaves: number;
  firstFace: number;
  numFaces: number;
}

export interface BSPEntity {
  classname: string;
  properties: Record<string, string>;
}

export interface ParsedBSP {
  header: BSPHeader;
  entities: BSPEntity[];
  planes: BSPPlane[];
  vertices: BSPVertex[];
  edges: BSPEdge[];
  surfEdges: number[];
  faces: BSPFace[];
  texInfos: BSPTexInfo[];
  textures: BSPMipTex[];
  models: BSPModel[];
  lightmapData: Uint8Array;
}
