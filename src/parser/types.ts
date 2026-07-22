export interface DemoHeader {
  magic: string;
  demoProtocol: number;
  networkProtocol: number;
  mapName: string;
  gameDir: string;
  playbackTime: number;
  frameCount: number;
  directoryOffset: number;
}

export interface DirectoryEntry {
  type: number;
  description: string;
  flags: number;
  cdTrack: number;
  trackTime: number;
  frameCount: number;
  offset: number;
  fileLength: number;
}

export enum FrameType {
  DEMO_START = 0,
  CONSOLE_COMMAND = 1,
  CLIENT_DATA = 2,
  NEXT_SECTION = 3,
  EVENT = 4,
  WEAPON_ANIM = 5,
  SOUND = 6,
  DEMO_BUFFER = 7,
}

export interface BaseFrame {
  type: FrameType;
  time: number;
  frame: number;
}

export interface DemoStartFrame extends BaseFrame {
  type: FrameType.DEMO_START;
}

export interface ConsoleCommandFrame extends BaseFrame {
  type: FrameType.CONSOLE_COMMAND;
  command: string;
}

export interface ClientDataFrame extends BaseFrame {
  type: FrameType.CLIENT_DATA;
  origin: [number, number, number];
  viewangles: [number, number, number];
  weaponBits: number;
  fov: number;
}

export interface NextSectionFrame extends BaseFrame {
  type: FrameType.NEXT_SECTION;
}

export interface EventFrame extends BaseFrame {
  type: FrameType.EVENT;
  flags: number;
  index: number;
  delay: number;
  eventArgs: EventArgs;
}

export interface EventArgs {
  flags: number;
  entityIndex: number;
  origin: [number, number, number];
  angles: [number, number, number];
  velocity: [number, number, number];
  ducking: boolean;
  fparam1: number;
  fparam2: number;
  iparam1: number;
  iparam2: number;
  bparam1: boolean;
  bparam2: boolean;
}

export interface WeaponAnimFrame extends BaseFrame {
  type: FrameType.WEAPON_ANIM;
  anim: number;
  body: number;
}

export interface SoundFrame extends BaseFrame {
  type: FrameType.SOUND;
  channel: number;
  sample: string;
  attenuation: number;
  volume: number;
  flags: number;
  pitch: number;
}

export interface DemoBufferFrame extends BaseFrame {
  type: FrameType.DEMO_BUFFER;
  buffer: Uint8Array;
}

export type DemoFrame =
  | DemoStartFrame
  | ConsoleCommandFrame
  | ClientDataFrame
  | NextSectionFrame
  | EventFrame
  | WeaponAnimFrame
  | SoundFrame
  | DemoBufferFrame;

export interface ParsedDemo {
  header: DemoHeader;
  directory: DirectoryEntry[];
  frames: DemoFrame[];
}

export interface PlayerState {
  index: number;
  name: string;
  team: 'CT' | 'T' | 'SPEC' | 'UNASSIGNED';
  origin: [number, number, number];
  angles: [number, number, number];
  health: number;
  armor: number;
  alive: boolean;
  weapon: string;
}

export interface GameEvent {
  time: number;
  type: 'kill' | 'round_start' | 'round_end' | 'bomb_plant' | 'bomb_defuse';
  data: Record<string, unknown>;
}
