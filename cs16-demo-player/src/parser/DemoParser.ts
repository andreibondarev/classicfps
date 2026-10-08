import {
  DemoHeader,
  DirectoryEntry,
  DemoFrame,
  FrameType,
  ParsedDemo,
  ClientDataFrame,
  ConsoleCommandFrame,
  EventFrame,
  EventArgs,
  WeaponAnimFrame,
  SoundFrame,
  DemoBufferFrame,
} from './types.ts';

export class DemoParser {
  private data: DataView;
  private buffer: Uint8Array;
  private offset: number = 0;

  constructor(arrayBuffer: ArrayBuffer) {
    this.buffer = new Uint8Array(arrayBuffer);
    this.data = new DataView(arrayBuffer);
  }

  parse(): ParsedDemo {
    const header = this.parseHeader();
    const directory = this.parseDirectory(header.directoryOffset);
    const frames = this.parseFrames(directory);

    return { header, directory, frames };
  }

  private parseHeader(): DemoHeader {
    const magic = this.readString(8);
    if (magic !== 'HLDEMO\0\0' && !magic.startsWith('HLDEMO')) {
      throw new Error(`Invalid demo file: expected HLDEMO magic, got "${magic}"`);
    }

    const demoProtocol = this.readInt32();
    const networkProtocol = this.readInt32();
    const mapName = this.readString(260).replace(/\0.*$/, '');
    const gameDir = this.readString(260).replace(/\0.*$/, '');
    this.readUint32(); // mapCRC - not used
    const directoryOffset = this.readInt32();

    // Calculate playback time and frame count from directory later
    return {
      magic,
      demoProtocol,
      networkProtocol,
      mapName,
      gameDir,
      playbackTime: 0,
      frameCount: 0,
      directoryOffset,
    };
  }

  private parseDirectory(offset: number): DirectoryEntry[] {
    this.offset = offset;
    const entryCount = this.readInt32();
    const entries: DirectoryEntry[] = [];

    for (let i = 0; i < entryCount; i++) {
      entries.push({
        type: this.readInt32(),
        description: this.readString(64).replace(/\0.*$/, ''),
        flags: this.readInt32(),
        cdTrack: this.readInt32(),
        trackTime: this.readFloat32(),
        frameCount: this.readInt32(),
        offset: this.readInt32(),
        fileLength: this.readInt32(),
      });
    }

    return entries;
  }

  private parseFrames(directory: DirectoryEntry[]): DemoFrame[] {
    const frames: DemoFrame[] = [];

    for (const entry of directory) {
      if (entry.type === 0 || entry.type === 1) {
        // Loading or playback segment
        this.offset = entry.offset;
        const endOffset = entry.offset + entry.fileLength;

        while (this.offset < endOffset) {
          try {
            const frame = this.parseFrame();
            if (frame) {
              frames.push(frame);
              if (frame.type === FrameType.NEXT_SECTION) {
                break;
              }
            }
          } catch {
            // Stop parsing this segment on error
            break;
          }
        }
      }
    }

    return frames;
  }

  private parseFrame(): DemoFrame | null {
    const type = this.readInt32() as FrameType; // Frame type is 4 bytes in GoldSrc
    const time = this.readFloat32();
    const frame = this.readInt32();

    switch (type) {
      case FrameType.DEMO_START:
        return { type, time, frame };

      case FrameType.CONSOLE_COMMAND:
        return this.parseConsoleCommand(time, frame);

      case FrameType.CLIENT_DATA:
        return this.parseClientData(time, frame);

      case FrameType.NEXT_SECTION:
        return { type, time, frame };

      case FrameType.EVENT:
        return this.parseEvent(time, frame);

      case FrameType.WEAPON_ANIM:
        return this.parseWeaponAnim(time, frame);

      case FrameType.SOUND:
        return this.parseSound(time, frame);

      case FrameType.DEMO_BUFFER:
        return this.parseDemoBuffer(time, frame);

      default:
        // Unknown frame type, try to skip
        return null;
    }
  }

  private parseConsoleCommand(time: number, frame: number): ConsoleCommandFrame {
    const command = this.readString(64).replace(/\0.*$/, '');
    return { type: FrameType.CONSOLE_COMMAND, time, frame, command };
  }

  private parseClientData(time: number, frame: number): ClientDataFrame {
    const origin: [number, number, number] = [
      this.readFloat32(),
      this.readFloat32(),
      this.readFloat32(),
    ];
    const viewangles: [number, number, number] = [
      this.readFloat32(),
      this.readFloat32(),
      this.readFloat32(),
    ];
    const weaponBits = this.readInt32();
    const fov = this.readFloat32();

    return {
      type: FrameType.CLIENT_DATA,
      time,
      frame,
      origin,
      viewangles,
      weaponBits,
      fov,
    };
  }

  private parseEvent(time: number, frame: number): EventFrame {
    const flags = this.readInt32();
    const index = this.readInt32();
    const delay = this.readFloat32();
    const eventArgs = this.parseEventArgs();

    return { type: FrameType.EVENT, time, frame, flags, index, delay, eventArgs };
  }

  private parseEventArgs(): EventArgs {
    return {
      flags: this.readInt32(),
      entityIndex: this.readInt32(),
      origin: [this.readFloat32(), this.readFloat32(), this.readFloat32()],
      angles: [this.readFloat32(), this.readFloat32(), this.readFloat32()],
      velocity: [this.readFloat32(), this.readFloat32(), this.readFloat32()],
      ducking: this.readInt32() !== 0,
      fparam1: this.readFloat32(),
      fparam2: this.readFloat32(),
      iparam1: this.readInt32(),
      iparam2: this.readInt32(),
      bparam1: this.readInt32() !== 0,
      bparam2: this.readInt32() !== 0,
    };
  }

  private parseWeaponAnim(time: number, frame: number): WeaponAnimFrame {
    const anim = this.readInt32();
    const body = this.readInt32();
    return { type: FrameType.WEAPON_ANIM, time, frame, anim, body };
  }

  private parseSound(time: number, frame: number): SoundFrame {
    const channel = this.readInt32();
    const sampleLength = this.readInt32();
    const sample = this.readString(sampleLength).replace(/\0.*$/, '');
    const attenuation = this.readFloat32();
    const volume = this.readFloat32();
    const flags = this.readInt32();
    const pitch = this.readInt32();

    return {
      type: FrameType.SOUND,
      time,
      frame,
      channel,
      sample,
      attenuation,
      volume,
      flags,
      pitch,
    };
  }

  private parseDemoBuffer(time: number, frame: number): DemoBufferFrame {
    const length = this.readInt32();
    const buffer = this.buffer.slice(this.offset, this.offset + length);
    this.offset += length;

    return { type: FrameType.DEMO_BUFFER, time, frame, buffer };
  }

  // Utility reading methods
  private readInt32(): number {
    const value = this.data.getInt32(this.offset, true); // Little endian
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
