import { ParsedDemo, DemoFrame, FrameType, ClientDataFrame, PlayerState, GameEvent } from '../parser/types.ts';

export interface TimelineEntry {
  time: number;
  frameIndex: number;
  playerStates: Map<number, PlayerState>;
}

export class GameState {
  private demo: ParsedDemo;
  private timeline: TimelineEntry[] = [];
  private events: GameEvent[] = [];

  // The recording player's state (from CLIENT_DATA frames)
  private recorderState: PlayerState;

  constructor(demo: ParsedDemo) {
    this.demo = demo;
    this.recorderState = this.createDefaultPlayer(0, 'Recorder');
    this.buildTimeline();
  }

  private createDefaultPlayer(index: number, name: string): PlayerState {
    return {
      index,
      name,
      team: 'UNASSIGNED',
      origin: [0, 0, 0],
      angles: [0, 0, 0],
      health: 100,
      armor: 0,
      alive: true,
      weapon: '',
    };
  }

  private buildTimeline(): void {
    // Sample at 20fps instead of every frame change (massive performance improvement)
    const SAMPLE_INTERVAL = 0.05; // 50ms = 20 samples per second
    let lastSampleTime = -SAMPLE_INTERVAL;
    const playerStates = new Map<number, PlayerState>();

    // Initialize recorder player
    playerStates.set(0, { ...this.recorderState });

    for (let i = 0; i < this.demo.frames.length; i++) {
      const frame = this.demo.frames[i];

      // Update state based on frame type
      if (frame.type === FrameType.CLIENT_DATA) {
        const clientData = frame as ClientDataFrame;
        const player = playerStates.get(0) || this.createDefaultPlayer(0, 'Recorder');
        player.origin = [...clientData.origin];
        player.angles = [...clientData.viewangles];
        playerStates.set(0, player);
      }

      // Sample at fixed intervals for performance
      const isValidTime = Number.isFinite(frame.time) && frame.time >= 0 && frame.time < 100000;
      if (isValidTime && frame.time >= lastSampleTime + SAMPLE_INTERVAL) {
        // Clone the current state for this timestamp
        const stateSnapshot = new Map<number, PlayerState>();
        for (const [id, state] of playerStates) {
          stateSnapshot.set(id, { ...state, origin: [...state.origin], angles: [...state.angles] });
        }

        this.timeline.push({
          time: frame.time,
          frameIndex: i,
          playerStates: stateSnapshot,
        });
        lastSampleTime = frame.time;
      }

      // Extract game events
      this.extractEvents(frame);
    }

    // Sort timeline by time
    this.timeline.sort((a, b) => a.time - b.time);
    console.log(`Timeline built: ${this.timeline.length} samples (20fps)`);
  }

  private extractEvents(frame: DemoFrame): void {
    if (frame.type === FrameType.CONSOLE_COMMAND) {
      const cmd = frame.command.toLowerCase();
      if (cmd.includes('kill') || cmd.includes('death')) {
        this.events.push({
          time: frame.time,
          type: 'kill',
          data: { command: frame.command },
        });
      }
    }

    if (frame.type === FrameType.SOUND) {
      const sample = frame.sample.toLowerCase();
      if (sample.includes('die') || sample.includes('death')) {
        this.events.push({
          time: frame.time,
          type: 'kill',
          data: { sound: frame.sample },
        });
      }
      if (sample.includes('bombpl')) {
        this.events.push({
          time: frame.time,
          type: 'bomb_plant',
          data: { sound: frame.sample },
        });
      }
      if (sample.includes('bombdef')) {
        this.events.push({
          time: frame.time,
          type: 'bomb_defuse',
          data: { sound: frame.sample },
        });
      }
    }
  }

  get mapName(): string {
    return this.demo.header.mapName;
  }

  get duration(): number {
    if (this.timeline.length === 0) return 0;
    return this.timeline[this.timeline.length - 1].time;
  }

  get frameCount(): number {
    return this.demo.frames.length;
  }

  get timelineLength(): number {
    return this.timeline.length;
  }

  getStateAtTime(time: number): TimelineEntry | null {
    if (this.timeline.length === 0) return null;

    // Binary search for the closest timeline entry
    let left = 0;
    let right = this.timeline.length - 1;

    while (left < right) {
      const mid = Math.floor((left + right + 1) / 2);
      if (this.timeline[mid].time <= time) {
        left = mid;
      } else {
        right = mid - 1;
      }
    }

    return this.timeline[left];
  }

  getInterpolatedState(time: number): Map<number, PlayerState> {
    if (this.timeline.length === 0) {
      return new Map();
    }

    // Binary search to find the entry at or before 'time'
    let left = 0;
    let right = this.timeline.length - 1;

    while (left < right) {
      const mid = Math.floor((left + right + 1) / 2);
      if (this.timeline[mid].time <= time) {
        left = mid;
      } else {
        right = mid - 1;
      }
    }

    const prevEntry = this.timeline[left];
    const nextEntry = left + 1 < this.timeline.length ? this.timeline[left + 1] : null;

    if (!nextEntry || prevEntry.time > time) {
      return prevEntry.playerStates;
    }

    // Interpolate between entries
    const t = (time - prevEntry.time) / (nextEntry.time - prevEntry.time);
    const interpolated = new Map<number, PlayerState>();

    for (const [id, prevState] of prevEntry.playerStates) {
      const nextState = nextEntry.playerStates.get(id);
      if (!nextState) {
        interpolated.set(id, { ...prevState });
        continue;
      }

      interpolated.set(id, {
        ...prevState,
        origin: [
          prevState.origin[0] + (nextState.origin[0] - prevState.origin[0]) * t,
          prevState.origin[1] + (nextState.origin[1] - prevState.origin[1]) * t,
          prevState.origin[2] + (nextState.origin[2] - prevState.origin[2]) * t,
        ],
        angles: [
          this.lerpAngle(prevState.angles[0], nextState.angles[0], t),
          this.lerpAngle(prevState.angles[1], nextState.angles[1], t),
          this.lerpAngle(prevState.angles[2], nextState.angles[2], t),
        ],
      });
    }

    return interpolated;
  }

  private lerpAngle(a: number, b: number, t: number): number {
    // Handle angle wrapping
    let diff = b - a;
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;
    return a + diff * t;
  }

  getEventsInRange(startTime: number, endTime: number): GameEvent[] {
    return this.events.filter(e => e.time >= startTime && e.time <= endTime);
  }
}
