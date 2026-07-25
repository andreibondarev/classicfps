import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import {
  initWasm,
  parseDemoWithProgress,
  parseBspTextured,
  parseMdl,
  parseMdlAttached,
  interpolateSoa,
  type SoaDemo,
  type PlayerInfo,
  type GameEvent,
  type TempEffect,
  type Vec3,
  type PlayerState,
  type InterpolationMode,
  type BspEntity,
} from './wasm.ts';
import {
  sampleWindowAt,
  verifyReplay,
  type ReplayVerificationReport,
} from './replayVerifier.ts';

interface DemoLibraryItem {
  name: string;
  path: string;
  url: string;
  map: string;
  size: number;
}

type HudMode = 'player' | 'broadcast' | 'minimal' | 'off';
type PlaybackMode = InterpolationMode;
type RenderQuality = 'auto' | 'high' | 'performance';
type HudTrackPoint = { time: number; a: number; b: number };
type ReplayBookmark = { id: string; time: number; label: string; follow: string | null };

class DemoPlayer {
  // Three.js
  private scene: THREE.Scene | null = null;
  private camera: THREE.PerspectiveCamera | null = null;
  private viewModelScene: THREE.Scene | null = null;
  private viewModelCamera: THREE.PerspectiveCamera | null = null;
  private renderer: THREE.WebGLRenderer | null = null;
  private controls: OrbitControls | null = null;
  private playerMesh: THREE.Group | null = null;
  private playerMeshes: Map<string, THREE.Group> = new Map();
  private mapMesh: THREE.Group | null = null;
  private dynamicBrushes: Array<{
    pivot: THREE.Group;
    mesh: THREE.Mesh;
    entity: BspEntity;
    kind: string;
    base: THREE.Vector3;
    boundsCenter: THREE.Vector3;
    extent: THREE.Vector3;
    path: THREE.Vector3[];
    destroyedTimes: number[];
  }> = [];
  private animatedMapMaterials: THREE.MeshBasicMaterial[] = [];
  private viewModel: THREE.Group | null = null;
  private viewModelWeapon: string | null = null;
  private viewModelRequest = 0;
  private viewModelEquippedAt = -Infinity;
  private viewMotionPosition: THREE.Vector3 | null = null;
  private viewMotionTime = -Infinity;
  private viewMotionSpeed = 0;

  // Demo state
  private timeline: SoaDemo | null = null;
  private duration: number = 0;
  private mapName: string = '';
  private players: PlayerInfo[] = [];
  private demoLibrary: DemoLibraryItem[] = [];
  private parsedDemoCache: Map<string, SoaDemo> = new Map();
  private demoSearch: string = '';
  private demoMapFilter: string = 'all';
  private demoIdentity: string = '';

  // Playback state
  private isPlaying: boolean = false;
  private playbackSpeed: number = 1.0;
  private playbackMode: PlaybackMode = 'cinematic';
  private renderQuality: RenderQuality = 'auto';
  private renderScale = Math.min(window.devicePixelRatio, 2);
  private frameTimeEma = 16.7;
  private qualityFrameCounter = 0;
  private timelineUiTick = -1;
  private currentTime: number = 0;
  private lastFrameTime: number = 0;
  private lastDisplayedEventIndex: number = -1;
  private killFeedEl: HTMLElement | null = null;
  private killCounts: Map<string, { k: number; d: number }> = new Map();
  private announceTimer: number = 0;
  private rosterSignature: string = '';
  private verificationReport: ReplayVerificationReport | null = null;
  private diagnosticsVisible: boolean = false;
  private diagnosticsLastRender: number = 0;
  private hudMode: HudMode = 'player';
  private hudTracks: Map<string, HudTrackPoint[]> = new Map();
  private hudLastSignature: string = '';
  private inventoryCacheKey = '';
  private inventoryCacheIds: number[] = [];
  private directorEnabled = false;
  private directorLastSwitch = -Infinity;
  private tacticalVisible = false;
  private economyVisible = false;
  private tacticalLastSample = -Infinity;
  private playerTrails: Map<string, Array<{ time: number; x: number; y: number }>> = new Map();
  private bookmarks: ReplayBookmark[] = [];
  private killReplayState: {
    returnTime: number;
    returnTarget: string | null;
    returnSpeed: number;
    eventTime: number;
  } | null = null;
  private clipRecording = false;
  private sharedLocationApplied = false;
  private sharedAutoLoadStarted = false;

  // DOM elements
  private dropOverlay: HTMLElement;
  private dropZone: HTMLElement;
  private canvasContainer: HTMLElement;
  private controlsEl: HTMLElement;
  private playBtn: HTMLButtonElement;
  private timelineEl: HTMLElement;
  private timelineProgress: HTMLElement;
  private timeDisplay: HTMLElement;
  private speedSelect: HTMLSelectElement;
  private infoPanel: HTMLElement;
  private mapNameEl: HTMLElement;
  private durationEl: HTMLElement;
  private playerCountEl: HTMLElement;
  private playerListPanel: HTMLElement;
  private playersEl: HTMLElement;
  private scoreboardEl: HTMLElement;
  private scoreCTEl: HTMLElement;
  private scoreTEl: HTMLElement;
  private roundTimerEl: HTMLElement;
  private roundTimerValueEl: HTMLElement;

  // Frozen player corpses (victim name -> corpse group)
  private deathMarkers: Map<string, THREE.Group> = new Map();

  // Follow camera (first-person)
  private followTarget: string | null = null;
  private preferredFollowTeam: 'CT' | 'T' | null = null;
  private cameraHistory: Array<string | null> = [];
  private restoringCameraHistory = false;
  private slowMotionReturnSpeed = 1;
  private smoothedEye: THREE.Vector3 | null = null;
  private smoothedForward: THREE.Vector3 | null = null;
  private cameraSmoothWallTime = 0;

  // Free-fly camera (noclip)
  private flyMode: boolean = false;
  private flyKeys: Set<string> = new Set();
  private flyYaw: number = 0;
  private flyPitch: number = 0;
  private lastAnimTime: number = 0;

  // Round navigation: start time of each round (index 0 = demo start)
  private rounds: number[] = [];

  // Per-player model changes over time [(time, model)], from ModelChange events
  private modelTimeline: Map<string, Array<[number, string]>> = new Map();
  // Authoritative TeamInfo history. This wins over model inference because
  // HLTV entity/model slots can briefly lag or be reassigned around spawns.
  private teamTimeline: Map<string, Array<[number, 'CT' | 'T']>> = new Map();

  // Stale-entity tracking: last time each player appeared in the entity stream
  private lastSeen: Map<string, number> = new Map();

  // Kill tracer lines currently fading out
  private tracers: Array<{ line: THREE.Line; expiresAt: number }> = [];

  // Last weapon each player killed with (drives the attached p_ model)
  private lastWeapon: Map<string, string> = new Map();

  // Raw .mdl file bytes by path (players + weapons share this)
  private mdlFileCache: Map<string, Promise<ArrayBuffer | null>> = new Map();

  // WAD bytes can be large, so only fetch each archive once.
  private wadFileCache: Map<string, Promise<ArrayBuffer | null>> = new Map();

  // Live non-player objects (grenades, C4) keyed by entity id
  private objectMeshes: Map<number, {
    group: THREE.Group; kind: number; lastSeen: number;
    stillSince?: number; detonated?: boolean;
  }> = new Map();

  // Demo-time-driven effects (smoke volumes, detonation flashes)
  private fx: Array<{ mesh: THREE.Object3D; bornT: number; ttl: number; kind: number }> = [];
  private readonly maxLiveEffects = 220;
  private readonly sharedFxGeometry = {
    smoke: new THREE.SphereGeometry(1, 12, 9),
    impact: new THREE.SphereGeometry(0.055, 8, 6),
    blood: new THREE.SphereGeometry(0.07, 8, 6),
    decal: new THREE.SphereGeometry(0.035, 8, 6),
    muzzle: new THREE.SphereGeometry(0.09, 8, 6),
    shell: new THREE.CylinderGeometry(0.012, 0.012, 0.045, 6),
  };
  private smokeTexture: THREE.CanvasTexture | null = null;

  // Bomb state (replayed from events)
  private bombPlantedAt: number | null = null;

  // Gunfire playback
  private lastShotT: number = -1;
  private lastRenderedShotBySlot: Map<number, number> = new Map();
  private lastDemoSoundT: number = -1;
  private lastNetworkSoundT: number = -1;
  private lastTempEffectT: number = -1;
  private audioCtx: AudioContext | null = null;
  private audioMaster: GainNode | null = null;
  private audioCompressor: DynamicsCompressorNode | null = null;
  private audioBuffers: Map<string, Promise<AudioBuffer | null>> = new Map();
  private activeAudioSources: Set<AudioBufferSourceNode> = new Set();
  private activeAudioChannels: Map<string, AudioBufferSourceNode> = new Map();
  private soundOn: boolean = true;
  private lastFallbackAudioT = -1;
  private nextFootstepAt: Map<string, number> = new Map();
  private missingAssets: Set<string> = new Set();
  private assetPreflight: { checked: number; missing: number; models: number; sounds: number } | null = null;
  private preloadScheduled = false;
  private lastPreloadTime = -Infinity;
  private deathsCacheTimeline: SoaDemo | null = null;
  private deathsCacheTime = Number.NaN;
  private deathsCache: Map<string, number> = new Map();

  // Player skin templates by model name (null = failed, use cylinder)
  private mdlCache: Map<string, Promise<{
    parsed: import('./wasm.ts').ParsedMdl;
    materials: THREE.Material[];
    uvAttr: THREE.BufferAttribute;
  } | null>> = new Map();

  // Score state
  private scoreCT: number = 0;
  private scoreT: number = 0;
  private roundTimerBaseSeconds: number | null = null;
  private roundTimerStartTime: number = 0;
  private readonly defaultRoundSeconds: number = 105;

  constructor() {
    // Get DOM elements
    this.dropOverlay = document.getElementById('drop-overlay')!;
    this.dropZone = this.dropOverlay.querySelector('.drop-zone')!;
    this.canvasContainer = document.getElementById('canvas-container')!;
    this.controlsEl = document.getElementById('controls')!;
    this.playBtn = document.getElementById('play-btn') as HTMLButtonElement;
    this.timelineEl = document.getElementById('timeline')!;
    this.timelineProgress = document.getElementById('timeline-progress')!;
    this.timeDisplay = document.getElementById('time-display')!;
    this.speedSelect = document.getElementById('speed-select') as HTMLSelectElement;
    this.infoPanel = document.getElementById('info-panel')!;
    this.mapNameEl = document.getElementById('map-name')!;
    this.durationEl = document.getElementById('duration')!;
    this.playerCountEl = document.getElementById('player-count')!;
    this.playerListPanel = document.getElementById('player-list')!;
    this.playersEl = document.getElementById('players')!;
    this.scoreboardEl = document.getElementById('match-bar')!;
    this.killFeedEl = document.getElementById('kill-feed')!;
    this.scoreCTEl = document.getElementById('score-ct')!;
    this.scoreTEl = document.getElementById('score-t')!;
    this.roundTimerEl = document.getElementById('round-timer')!;
    this.roundTimerValueEl = document.getElementById('round-timer-value')!;

    this.init();
  }

  private async init(): Promise<void> {
    // Initialize WASM
    await initWasm();

    // Setup Three.js
    this.setupThreeJS();

    // Setup event listeners
    this.setupEventListeners();

    const savedHudMode = localStorage.getItem('cs16-hud-mode');
    if (savedHudMode && ['player', 'broadcast', 'minimal', 'off'].includes(savedHudMode)) {
      this.hudMode = savedHudMode as HudMode;
    }
    this.setHudMode(this.hudMode, false);
    const savedPlaybackMode = localStorage.getItem('cs16-playback-mode');
    if (savedPlaybackMode === 'authentic' || savedPlaybackMode === 'cinematic') {
      this.playbackMode = savedPlaybackMode;
    }
    this.setPlaybackMode(this.playbackMode, false);
    const savedQuality = localStorage.getItem('cs16-render-quality');
    if (savedQuality === 'auto' || savedQuality === 'high' || savedQuality === 'performance') {
      this.renderQuality = savedQuality;
    }
    this.setRenderQuality(this.renderQuality, false);

    // Populate the landing-page archive from the local demos directory.
    void this.loadDemoLibrary();
  }

  private setupThreeJS(): void {
    // Scene
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x1a1a2e);

    // Camera
    this.camera = new THREE.PerspectiveCamera(
      60,
      this.canvasContainer.clientWidth / this.canvasContainer.clientHeight,
      0.1,
      10000
    );
    this.camera.position.set(0, 50, 50);
    this.scene.add(this.camera);

    // Render the first-person weapon separately from the world. GoldSrc uses a
    // much nearer clip plane for viewmodels; putting these meshes in the world
    // camera clips the hands and greatly exaggerates whichever arm is closest.
    this.viewModelScene = new THREE.Scene();
    this.viewModelCamera = new THREE.PerspectiveCamera(
      this.camera.fov,
      this.camera.aspect,
      0.005,
      10,
    );
    this.viewModel = new THREE.Group();
    this.viewModel.name = 'firstPersonViewModel';
    this.viewModel.visible = false;
    this.viewModelScene.add(this.viewModel);

    // Renderer
    // MSAA is expensive on the large, texture-grouped BSP surface and cannot
    // be disabled later when Auto/Performance quality reacts to a slow GPU.
    // Native-resolution texture filtering keeps the retro geometry crisp
    // without forcing every frame through a multisampled render target.
    this.renderer = new THREE.WebGLRenderer({
      antialias: false,
      powerPreference: 'high-performance',
    });
    this.renderer.setSize(this.canvasContainer.clientWidth, this.canvasContainer.clientHeight);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.canvasContainer.appendChild(this.renderer.domElement);

    // Controls
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;

    // Lighting
    this.scene.add(new THREE.AmbientLight(0xffffff, 0.6));
    const dirLight = new THREE.DirectionalLight(0xffffff, 0.8);
    dirLight.position.set(50, 100, 50);
    this.scene.add(dirLight);

    // Grid (default, hidden when map loads)
    const grid = new THREE.GridHelper(1000, 100, 0x444466, 0x333355);
    grid.name = 'grid';
    this.scene.add(grid);

    // Player mesh
    this.createPlayerMesh();

    // Handle resize
    window.addEventListener('resize', () => this.onResize());

    // Render loop
    this.animate();
  }

  private createPlayerMesh(): void {
    // Create default recorder mesh (green)
    this.playerMesh = this.createSinglePlayerMesh(0x81c784);
    this.playerMesh.visible = false;
    this.scene!.add(this.playerMesh);
  }

  private createSinglePlayerMesh(color: number): THREE.Group {
    const SCALE = 0.01;
    // Player dimensions - slightly enlarged for visibility
    const HEIGHT = 72 * SCALE * 2.5;  // ~1.8 units
    const RADIUS = 16 * SCALE * 2;    // ~0.32 units (keep width reasonable)

    const group = new THREE.Group();

    // Yaw pivot: everything that should turn with the player's view direction
    const pivot = new THREE.Group();
    pivot.name = 'yawPivot';
    group.add(pivot);

    // Body cylinder retired: skins carry the visuals. Kept (hidden) only as
    // a raycast target for the aim label.
    const body = new THREE.Mesh(
      new THREE.CylinderGeometry(RADIUS * 0.4, RADIUS * 0.4, HEIGHT * 0.4, 8),
      new THREE.MeshStandardMaterial({ color })
    );
    body.position.y = HEIGHT * 0.2;
    body.name = 'body';
    body.visible = false;
    pivot.add(body);

    return group;
  }

  /// Retint fallback player geometry when their side changes.
  /// Skin meshes keep their real textures (materials are shared with clones).
  private recolorPlayerMesh(mesh: THREE.Group, color: number): void {
    if (mesh.userData.color === color) return;
    mesh.userData.color = color;
    mesh.traverse((obj) => {
      if (obj instanceof THREE.Mesh && obj.name !== 'skinMesh') {
        const mat = obj.material as THREE.MeshStandardMaterial | THREE.MeshBasicMaterial;
        mat.color.setHex(color);
        if ('emissive' in mat) (mat as THREE.MeshStandardMaterial).emissive.setHex(color);
      }
    });
  }

  /// Load and cache a parsed model: shared materials + uv attribute + anims.
  private loadPlayerModelTemplate(model: string): Promise<{
    parsed: import('./wasm.ts').ParsedMdl;
    materials: THREE.Material[];
    uvAttr: THREE.BufferAttribute;
  } | null> {
    let cached = this.mdlCache.get(model);
    if (cached) return cached;
    cached = (async () => {
      try {
        const buf = await this.fetchMdl(model);
        if (!buf) return null;
        // Weapons are bone-merged onto the owning player's skeleton
        let parsed: import('./wasm.ts').ParsedMdl;
        const pipe = model.indexOf('|');
        if (pipe >= 0) {
          const playerBuf = await this.fetchMdl(model.slice(0, pipe));
          const weaponBuf = await this.fetchMdl(model.slice(pipe + 1));
          if (!playerBuf || !weaponBuf) return null;
          parsed = await parseMdlAttached(playerBuf, weaponBuf);
        } else {
          parsed = await parseMdl(buf);
        }

        const materials = parsed.groups.map((g) => {
          if (g.pix_offset >= 0 && g.width > 0) {
            const pixels = parsed.pixels.subarray(g.pix_offset, g.pix_offset + g.width * g.height * 4);
            const tex = new THREE.DataTexture(pixels, g.width, g.height, THREE.RGBAFormat);
            tex.magFilter = THREE.LinearFilter;
            tex.minFilter = THREE.LinearMipmapLinearFilter;
            tex.generateMipmaps = true;
            tex.colorSpace = THREE.SRGBColorSpace;
            tex.needsUpdate = true;
            return new THREE.MeshBasicMaterial({ map: tex, side: THREE.DoubleSide });
          }
          return new THREE.MeshBasicMaterial({ color: 0x888888 });
        });
        const uvAttr = new THREE.BufferAttribute(parsed.uvs, 2);
        return { parsed, materials, uvAttr };
      } catch (e) {
        console.warn(`Model ${model} failed:`, e);
        return null;
      }
    })();
    this.mdlCache.set(model, cached);
    return cached;
  }

  private reportMissingAsset(path: string): void {
    if (!path || this.missingAssets.has(path)) return;
    this.missingAssets.add(path);
    const status = document.getElementById('asset-status');
    if (!status) return;
    const count = this.missingAssets.size;
    status.textContent = `${count} OPTIONAL ASSET${count === 1 ? '' : 'S'} UNAVAILABLE`;
    status.title = [...this.missingAssets].sort().join('\n');
    status.classList.remove('hidden');
  }

  /// Fetch raw .mdl bytes (cached). Composite "player|p_weapon" keys fetch the player part.
  private fetchMdl(model: string): Promise<ArrayBuffer | null> {
    const base = model.includes('|') ? model.split('|')[0] : model;
    const path = base.startsWith('p_') || base.startsWith('v_') || base.startsWith('w_')
      || base.startsWith('shield/')
      ? `models/weapons/${base}.mdl`
      : `models/player/${base}/${base}.mdl`;
    let cached = this.mdlFileCache.get(path);
    if (!cached) {
      cached = (async () => {
        try {
          const resp = await fetch(path);
          if (!resp.ok) {
            this.reportMissingAsset(path);
            return null;
          }
          const buf = await resp.arrayBuffer();
          if (buf.byteLength < 4 || new DataView(buf).getUint32(0, true) !== 0x54534449) {
            this.reportMissingAsset(path);
            return null;
          }
          return buf; // "IDST"
        } catch {
          this.reportMissingAsset(path);
          return null;
        }
      })();
      this.mdlFileCache.set(path, cached);
    }
    return cached;
  }

  /// Build a per-player mesh instance: own position buffer (for animation),
  /// shared uvs/materials.
  private buildSkinInstance(t: {
    parsed: import('./wasm.ts').ParsedMdl;
    materials: THREE.Material[];
    uvAttr: THREE.BufferAttribute;
  }, name: string): THREE.Group {
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(t.parsed.positions.slice(), 3));
    geometry.setAttribute('uv', t.uvAttr);
    t.parsed.groups.forEach((g, i) => geometry.addGroup(g.vert_start, g.vert_count, i));
    const mesh = new THREE.Mesh(geometry, t.materials);
    mesh.name = 'skinMesh';
    const group = new THREE.Group();
    group.name = name;
    // Models face +X in GoldSrc; our yaw pivot's forward is +Z
    group.rotation.y = -Math.PI / 2;
    group.add(mesh);
    group.userData.anims = t.parsed.anims;
    group.userData.seqLabels = t.parsed.seqLabels;
    group.userData.frame = -1;
    return group;
  }

  /// Swap a player's visual to the given model skin (async, idempotent)
  private applySkin(mesh: THREE.Group, model: string): void {
    if (mesh.userData.skinModel === model) return;
    mesh.userData.skinModel = model;
    this.loadPlayerModelTemplate(model).then((template) => {
      // Player may have switched again while loading
      if (mesh.userData.skinModel !== model) return;
      const pivot = mesh.getObjectByName('yawPivot');
      if (!pivot) return;
      const old = pivot.getObjectByName('skin');
      if (old) pivot.remove(old);
      if (!template) return; // keep cylinder fallback

      pivot.add(this.buildSkinInstance(template, 'skin'));
      // A seek can be paused while the asynchronous model request finishes.
      // Re-apply the current replay state immediately so the freshly attached
      // mesh never remains in its bind pose until playback resumes.
      if (!this.isPlaying) this.updatePlayback();
    });
  }

  /// Attach the given p_ weapon model to a player's hands (bind pose aligns
  /// with the player skeleton's reference pose).
  private applyWeapon(mesh: THREE.Group, weaponModel: string): void {
    if (mesh.userData.weaponModel === weaponModel) return;
    mesh.userData.weaponModel = weaponModel;
    this.loadPlayerModelTemplate(weaponModel).then((template) => {
      if (mesh.userData.weaponModel !== weaponModel) return;
      const pivot = mesh.getObjectByName('yawPivot');
      if (!pivot) return;
      const old = pivot.getObjectByName('weapon');
      if (old) pivot.remove(old);
      if (!template) return;
      pivot.add(this.buildSkinInstance(template, 'weapon'));
      if (!this.isPlaying) this.updatePlayback();
    });
  }

  /// Advance a skin (or weapon) group's baked animation for this frame.
  /// The recorded sequence label selects the family; locomotion cycles use replay time.
  private tickSkinAnimation(
    group: THREE.Group,
    moving: boolean,
    recordedLabel?: string,
    recordedFrame?: number,
  ): void {
    const anims = group.userData.anims as import('./wasm.ts').MdlAnim[] | undefined;
    if (!anims?.length) return;
    const g = (recordedLabel ?? '').toLowerCase();
    const crouched = g.includes('crouch');
    const want = g.includes('die') || g.includes('death')
      ? 'die'
      : g.includes('shoot') || g.includes('attack') || g.includes('fire')
        ? 'shoot'
        : crouched
          ? (moving || g.includes('run') || g.includes('walk') ? 'crouchrun' : 'crouchidle')
          : (moving || g.includes('run') || g.includes('walk') ? 'run' : 'idle');
    // Main-sequence frames are authoritative for discrete actions. The MDL
    // parser preserves every original sequence in index order, so prefer its
    // exact label before falling back to broad compatibility families.
    const exactAnim = recordedFrame !== undefined
      ? anims.find((animation) => animation.name === g && animation.frames > 0)
      : undefined;
    const anim = exactAnim
      ?? anims.find((a) => a.name === want)
      ?? (moving ? anims.find((a) => a.name === 'run') : anims.find((a) => a.name === 'idle'))
      ?? anims[0];
    if (!anim || anim.frames <= 0 || !anim.data.length) return;
    const framePosition = recordedFrame !== undefined
      ? Math.min(anim.frames - 1, (recordedFrame / 255) * Math.max(0, anim.frames - 1))
      : (this.currentTime * anim.fps) % anim.frames;
    const frame = Math.floor(framePosition);
    const nextFrame = recordedFrame !== undefined
      ? Math.min(anim.frames - 1, frame + 1)
      : (frame + 1) % anim.frames;
    const frameMix = this.playbackMode === 'cinematic' ? framePosition - frame : 0;
    const key = `${anim.name}:${framePosition.toFixed(2)}:${this.playbackMode}`;
    if (group.userData.frame === key) return;
    group.userData.frame = key;
    const skinMesh = group.getObjectByName('skinMesh') as THREE.Mesh | undefined;
    if (!skinMesh) return;
    const attr = skinMesh.geometry.getAttribute('position') as THREE.BufferAttribute;
    const n = attr.array.length;
    const offset = frame * n;
    const nextOffset = nextFrame * n;
    if (offset + n > anim.data.length || nextOffset + n > anim.data.length) return;

    const output = attr.array as Float32Array;
    if (this.playbackMode === 'cinematic'
        && group.userData.animName
        && group.userData.animName !== anim.name) {
      group.userData.transitionFrom = output.slice();
      group.userData.transitionAt = this.currentTime;
    }
    group.userData.animName = anim.name;
    const transitionFrom = group.userData.transitionFrom as Float32Array | undefined;
    const transitionAge = this.currentTime - (group.userData.transitionAt as number ?? -1);
    const transitionMix = transitionFrom && transitionAge >= 0 && transitionAge < 0.12
      ? transitionAge / 0.12
      : 1;
    if (transitionMix >= 1) group.userData.transitionFrom = undefined;

    for (let i = 0; i < n; i++) {
      const target = anim.data[offset + i]
        + (anim.data[nextOffset + i] - anim.data[offset + i]) * frameMix;
      output[i] = transitionMix < 1 && transitionFrom
        ? transitionFrom[i] + (target - transitionFrom[i]) * transitionMix
        : target;
    }
    attr.needsUpdate = true;
  }

  /// Resolve a weaponmodel index to a p_ model basename via the resource table
  private weaponModelName(index: number): string | null {
    if (!index || !this.timeline?.model_names) return null;
    const entry = this.timeline.model_names.find(([i]) => i === index);
    if (!entry) return null;
    const m = entry[1].match(/p_[a-z0-9]+/);
    return m ? m[0] : null;
  }

  /// Weapon model for a player: authoritative from the entity's weaponmodel
  /// index when present, else last weapon they killed with, else team rifle.
  private weaponFor(name: string, entityWeapon?: number): string {
    const exact = entityWeapon !== undefined ? this.weaponModelName(entityWeapon) : null;
    if (exact) return exact;
    return this.weaponForHeuristic(name);
  }

  private weaponForHeuristic(name: string): string {
    const WEAPON_MODELS: Record<string, string> = {
      ak47: 'p_ak47', m4a1: 'p_m4a1', awp: 'p_awp', deagle: 'p_deagle', usp: 'p_usp',
      glock18: 'p_glock18', glock: 'p_glock18', famas: 'p_famas', galil: 'p_galil',
      scout: 'p_scout', sg552: 'p_sg552', aug: 'p_aug', mp5navy: 'p_mp5', p90: 'p_p90',
      mac10: 'p_mac10', tmp: 'p_tmp', ump45: 'p_ump45', m3: 'p_m3', xm1014: 'p_xm1014',
      m249: 'p_m249', p228: 'p_p228', elite: 'p_elite', fiveseven: 'p_fiveseven',
      sg550: 'p_sg550', g3sg1: 'p_g3sg1', knife: 'p_knife', hegrenade: 'p_hegrenade',
    };
    const last = this.lastWeapon.get(name);
    if (last && WEAPON_MODELS[last]) return WEAPON_MODELS[last];
    const team = this.teamAt(name, this.currentTime);
    return team === 'CT' ? 'p_m4a1' : 'p_ak47';
  }

  private deathAnimation(
    anims: import('./wasm.ts').MdlAnim[] | undefined,
    name: string,
    deathTime: number,
  ): import('./wasm.ts').MdlAnim | undefined {
    const candidates = anims?.filter((anim) =>
      anim.frames > 0
      && anim.data.length > 0
      && /death|die|gutshot|headshot|crouch_die|back|forward/i.test(anim.name));
    if (!candidates?.length) return anims?.find((anim) => anim.name === 'die' && anim.frames > 0);
    let hash = Math.round(deathTime * 10);
    for (let index = 0; index < name.length; index++) {
      hash = ((hash * 31) ^ name.charCodeAt(index)) >>> 0;
    }
    return candidates[hash % candidates.length];
  }

  private createCorpse(name: string, deathTime: number, yaw: number): THREE.Group {
    const group = new THREE.Group();
    group.name = `corpse:${name}`;
    const pivot = new THREE.Group();
    pivot.name = 'yawPivot';
    pivot.rotation.y = THREE.MathUtils.degToRad(yaw + 90);
    group.add(pivot);

    // Build a separate skin instance so its final death frame remains frozen
    // while the live player mesh is reused after the next round starts.
    const model = this.modelAt(name, deathTime);
    if (model) {
      void this.loadPlayerModelTemplate(model).then((template) => {
        if (!template || this.deathMarkers.get(name) !== group) return;
        const skin = this.buildSkinInstance(template, 'corpseSkin');
        const anims = skin.userData.anims as import('./wasm.ts').MdlAnim[] | undefined;
        const die = this.deathAnimation(anims, name, deathTime);
        const mesh = skin.getObjectByName('skinMesh') as THREE.Mesh | undefined;
        const attribute = mesh?.geometry.getAttribute('position') as THREE.BufferAttribute | undefined;
        if (die && mesh && attribute && die.frames > 0) {
          const values = attribute.array.length;
          const offset = (die.frames - 1) * values;
          if (offset + values <= die.data.length) {
            (attribute.array as Float32Array).set(die.data.subarray(offset, offset + values));
            attribute.needsUpdate = true;
            mesh.geometry.computeBoundingBox();
            mesh.geometry.computeBoundingSphere();
            // Death sequences can move every vertex outside the bind-pose
            // bounds used by Three.js's automatic frustum test.
            mesh.frustumCulled = false;
            skin.userData.frame = `corpse:${die.frames - 1}`;
          }
        }
        pivot.add(skin);
      });
    }
    return group;
  }

  private static teamOfModel(model: string): 'CT' | 'T' | null {
    if (['gign', 'sas', 'gsg9', 'urban', 'vip'].some((m) => model.includes(m))) return 'CT';
    if (['arctic', 'leet', 'guerilla', 'terror'].some((m) => model.includes(m))) return 'T';
    return null;
  }

  /// Player model at a given demo time (side switches at halftime), falling
  /// back to the static roster model.
  private modelAt(name: string, time: number): string {
    const changes = this.modelTimeline.get(name);
    let model = this.players.find((p) => p.name === name)?.model ?? '';
    if (changes) {
      for (const [t, m] of changes) {
        if (t <= time) model = m;
        else break;
      }
    }
    return model;
  }

  private teamAt(name: string, time: number): 'CT' | 'T' | null {
    const changes = this.teamTimeline.get(name);
    let recorded: 'CT' | 'T' | null = null;
    if (changes) {
      for (const [changeTime, team] of changes) {
        if (changeTime <= time) recorded = team;
        else break;
      }
    }
    if (recorded) return recorded;
    const byModel = DemoPlayer.teamOfModel(this.modelAt(name, time));
    if (byModel) return byModel;
    const player = this.players.find((candidate) => candidate.name === name);
    if (player?.team === 'CT') return 'CT';
    if (player?.team === 'TERRORIST') return 'T';
    return null;
  }

  private teamOf(player: PlayerInfo, time?: number): 'CT' | 'T' | null {
    if (time !== undefined) return this.teamAt(player.name, time);
    const model = time !== undefined ? this.modelAt(player.name, time) : player.model || '';
    const byModel = DemoPlayer.teamOfModel(model);
    if (byModel) return byModel;
    if (player.team === 'CT') return 'CT';
    if (player.team === 'TERRORIST') return 'T';
    return null;
  }

  private teamColorFor(name: string, time?: number): number {
    const t = time ?? this.currentTime;
    const team = this.teamAt(name, t);
    if (team === 'CT') return 0x4fc3f7;
    if (team === 'T') return 0xffd54f;
    return 0x81c784;
  }

  // Players dead at `time`: victims of Kill/Suicide since the last round start.
  // Recomputed from the event list each frame so seeking stays consistent.
  private computeDeaths(time: number): Map<string, number> {
    if (this.deathsCacheTimeline === this.timeline && this.deathsCacheTime === time) {
      return this.deathsCache;
    }
    const deaths = new Map<string, number>();
    const events = this.timeline?.events;
    if (!events) return deaths;

    for (const event of events) {
      if (event.time > time) break;
      if (event.event_type === 'RoundStart') {
        deaths.clear();
      } else if (event.event_type === 'Kill' || event.event_type === 'Suicide') {
        if (event.data.victim) deaths.set(event.data.victim, event.time);
      }
    }
    this.deathsCacheTimeline = this.timeline;
    this.deathsCacheTime = time;
    this.deathsCache = deaths;
    return deaths;
  }

  // Last known transform at or before `time` (for placing a frozen corpse).
  private findStateBefore(name: string, time: number): { origin: Vec3; angles: Vec3 } | null {
    const d = this.timeline;
    if (!d || d.times.length === 0) return null;
    const slot = d.slot_names.indexOf(name);
    if (slot < 0) return null;
    const nSlots = d.slot_names.length;

    let left = 0;
    let right = d.times.length - 1;
    while (left < right) {
      const mid = (left + right + 1) >> 1;
      if (d.times[mid] <= time) left = mid;
      else right = mid - 1;
    }

    // Scan backwards a bounded window in case the player is missing from recent entries
    const limit = Math.max(0, left - 400);
    for (let i = left; i >= limit; i--) {
      if (d.presence[i * nSlots + slot]) {
        const base = (i * nSlots + slot) * 3;
        return {
          origin: {
            x: d.positions[base],
            y: d.positions[base + 1],
            z: d.positions[base + 2],
          },
          angles: {
            x: d.angles[base],
            y: d.angles[base + 1],
            z: d.angles[base + 2],
          },
        };
      }
    }
    return null;
  }

  private updateDeathMarkers(deaths: Map<string, number>): void {
    const SCALE = 0.01;

    // Remove markers for players no longer dead (round restart or backward seek)
    for (const [name, marker] of this.deathMarkers) {
      if (!deaths.has(name)) {
        this.scene!.remove(marker);
        this.deathMarkers.delete(name);
      }
    }

    for (const [name, deathTime] of deaths) {
      // Fresh deaths: play the one-shot die animation on the body first
      const elapsed = this.currentTime - deathTime;
      const bodyMesh = this.playerMeshes.get(name);
      const pivot = bodyMesh?.getObjectByName('yawPivot');
      const skin = pivot?.getObjectByName('skin') as THREE.Group | undefined;
      const dieAnim = this.deathAnimation(
        skin?.userData.anims as import('./wasm.ts').MdlAnim[] | undefined,
        name,
        deathTime,
      );
      if (bodyMesh && skin && dieAnim && elapsed >= 0 && elapsed < 2.4) {
        bodyMesh.visible = true;
        const frame = Math.min(Math.floor(elapsed * dieAnim.fps), dieAnim.frames - 1);
        const key = `die:${frame}`;
        if (skin.userData.frame !== key) {
          skin.userData.frame = key;
          const skinMesh = skin.getObjectByName('skinMesh') as THREE.Mesh | undefined;
          const attr = skinMesh?.geometry.getAttribute('position') as THREE.BufferAttribute | undefined;
          if (attr) {
            const n = attr.array.length;
            const off = frame * n;
            if (off + n <= dieAnim.data.length) {
              (attr.array as Float32Array).set(dieAnim.data.subarray(off, off + n));
              attr.needsUpdate = true;
            }
          }
        }
        continue; // frozen corpse appears after the body settles
      }

      let marker = this.deathMarkers.get(name);
      // Recreate if the death time changed (e.g. seek to a different round)
      if (marker && marker.userData.deathTime !== deathTime) {
        this.scene!.remove(marker);
        this.deathMarkers.delete(name);
        marker = undefined;
      }
      if (!marker) {
        const state = this.findStateBefore(name, deathTime);
        if (!state) continue;
        marker = this.createCorpse(name, deathTime, state.angles.y);
        marker.position.set(
          state.origin.x * SCALE,
          state.origin.z * SCALE,
          -state.origin.y * SCALE,
        );
        marker.userData.deathTime = deathTime;
        this.scene!.add(marker);
        this.deathMarkers.set(name, marker);
      }

      // Hide the body mesh while the player is dead
      const mesh = this.playerMeshes.get(name);
      if (mesh) mesh.visible = false;
    }
  }

  /// GoldSrc FOV values are horizontal degrees at a canonical 4:3 aspect.
  /// Keeping the corresponding vertical angle gives modern widescreen output
  /// more peripheral vision without changing the recorded aim direction.
  private goldSrcFovToVertical(horizontalDegrees: number): number {
    const horizontal = THREE.MathUtils.degToRad(
      THREE.MathUtils.clamp(horizontalDegrees, 1, 179),
    );
    const vertical = 2 * Math.atan(Math.tan(horizontal / 2) / (4 / 3));
    return THREE.MathUtils.radToDeg(vertical);
  }

  private setFollowTarget(name: string | null, recordHistory = true): void {
    if (
      name
      && name !== 'Spectator Camera'
      && this.timeline
      && this.computeDeaths(this.currentTime).has(name)
    ) {
      this.showAnnouncement('POV unavailable · player is dead', '#ff9b77');
      return;
    }
    if (name !== null && this.flyMode) this.exitFlyMode();
    const changed = name !== this.followTarget;
    if (changed && recordHistory && !this.restoringCameraHistory) {
      this.cameraHistory.push(this.followTarget);
      if (this.cameraHistory.length > 40) this.cameraHistory.shift();
    }
    if (name && name !== 'Spectator Camera') {
      this.preferredFollowTeam = this.teamAt(name, this.currentTime) ?? this.preferredFollowTeam;
    }
    if (changed && this.playbackMode === 'cinematic' && this.followTarget !== null && name !== null) {
      this.playPovTransition();
    }
    this.followTarget = name;
    this.smoothedEye = changed ? this.camera?.position.clone() ?? null : this.smoothedEye;
    if (changed) this.smoothedForward = null;
    this.cameraSmoothWallTime = performance.now();
    if (changed) {
      this.viewMotionPosition = null;
      this.viewMotionTime = -Infinity;
      this.viewMotionSpeed = 0;
    }
    this.controls!.enabled = name === null;
    // GoldSrc reports horizontal FOV for a canonical 4:3 viewport, whereas
    // Three.js expects vertical FOV.
    if (this.camera) {
      this.camera.fov = name !== null ? this.goldSrcFovToVertical(90) : 60;
      this.camera.updateProjectionMatrix();
    }
    this.updateFollowHud();
    // Refresh highlight in the player list
    for (const el of this.playersEl.querySelectorAll('.player-entry')) {
      el.classList.toggle('following', (el as HTMLElement).dataset.name === name);
    }
    // Hide the followed player's own mesh in first-person; restore otherwise
    this.updatePlayback();
  }

  private livingFollowTargets(teamOnly = false): string[] {
    const deaths = this.computeDeaths(this.currentTime);
    const available = this.players
      .filter((player) => !deaths.has(player.name))
      .sort((left, right) => left.index - right.index);
    const preferred = this.preferredFollowTeam;
    const sameTeam = preferred
      ? available.filter((player) => this.teamAt(player.name, this.currentTime) === preferred)
      : [];
    const ordered = teamOnly ? sameTeam : [
      ...sameTeam,
      ...available.filter((player) => !sameTeam.includes(player)),
    ];
    return ordered.map((player) => player.name);
  }

  private cycleFollowTarget(direction: -1 | 1): void {
    const targets = this.livingFollowTargets();
    if (!targets.length) {
      this.showAnnouncement('No living players available', '#ff9b77');
      return;
    }
    const current = this.followTarget ? targets.indexOf(this.followTarget) : -1;
    const next = current < 0
      ? (direction > 0 ? 0 : targets.length - 1)
      : (current + direction + targets.length) % targets.length;
    this.setFollowTarget(targets[next]);
  }

  private restorePreviousCamera(): void {
    while (this.cameraHistory.length) {
      const target = this.cameraHistory.pop() ?? null;
      if (target === this.followTarget) continue;
      if (target && target !== 'Spectator Camera' && this.computeDeaths(this.currentTime).has(target)) continue;
      this.restoringCameraHistory = true;
      this.setFollowTarget(target, false);
      this.restoringCameraHistory = false;
      return;
    }
    this.showAnnouncement('No previous camera', '#9eb0bf');
  }

  private toggleSlowMotion(): void {
    if (this.playbackSpeed === 0.25) {
      this.playbackSpeed = this.slowMotionReturnSpeed || 1;
    } else {
      this.slowMotionReturnSpeed = this.playbackSpeed;
      this.playbackSpeed = 0.25;
    }
    this.speedSelect.value = String(this.playbackSpeed);
    this.showAnnouncement(`${this.playbackSpeed}× playback`, '#81d4fa');
  }

  private playPovTransition(): void {
    let overlay = document.getElementById('pov-transition');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.id = 'pov-transition';
      this.canvasContainer.appendChild(overlay);
    }
    overlay.classList.remove('active');
    void overlay.offsetWidth;
    overlay.classList.add('active');
  }

  /// CS-style crosshair overlay, shown only in first-person
  private updateCrosshair(): void {
    let ch = document.getElementById('fp-crosshair');
    if (!this.followTarget || this.hudMode === 'off') {
      ch?.remove();
      return;
    }
    if (!ch) {
      ch = document.createElement('div');
      ch.id = 'fp-crosshair';
      ch.style.cssText = `
        position: absolute;
        left: 50%;
        top: 50%;
        transform: translate(-50%, -50%);
        pointer-events: none;
        z-index: 999;
      `;
      const arm = (x: string) => `
        position: absolute;
        background: #00e000;
        box-shadow: 0 0 2px rgba(0,0,0,0.9);
        ${x}
      `;
      for (const style of [
        arm('left: -11px; top: -1px; width: 7px; height: 2px;'),
        arm('left: 4px; top: -1px; width: 7px; height: 2px;'),
        arm('left: -1px; top: -11px; width: 2px; height: 7px;'),
        arm('left: -1px; top: 4px; width: 2px; height: 7px;'),
      ]) {
        const el = document.createElement('div');
        el.style.cssText = style;
        ch.appendChild(el);
      }
      const label = document.createElement('div');
      label.id = 'fp-aim-label';
      label.style.cssText = `
        position: absolute;
        top: 18px;
        left: 50%;
        transform: translateX(-50%);
        font-size: 12px;
        font-family: monospace;
        white-space: nowrap;
        text-shadow: 0 0 3px #000;
      `;
      ch.appendChild(label);
      // The renderer fills canvasContainer, not the full viewport (playback
      // controls occupy the bottom). Centering against document.body put the
      // crosshair below the camera's actual optical axis.
      this.canvasContainer.appendChild(ch);
    }
  }

  /// Show the name of the player under the crosshair (raycast from camera)
  private updateAimLabel(): void {
    const label = document.getElementById('fp-aim-label');
    if (!label || !this.camera) return;

    const ray = new THREE.Raycaster();
    ray.setFromCamera(new THREE.Vector2(0, 0), this.camera);
    ray.far = 50;

    const bodies: THREE.Object3D[] = [];
    for (const [name, mesh] of this.playerMeshes) {
      if (!mesh.visible || name === this.followTarget) continue;
      const body = mesh.getObjectByName('body');
      if (body) bodies.push(body);
    }
    const hits = ray.intersectObjects(bodies, false);
    const hit = hits[0]?.object.parent?.parent as THREE.Group | undefined;
    const name = hit?.userData.playerName as string | undefined;
    if (name) {
      const color = this.teamColorFor(name).toString(16).padStart(6, '0');
      label.textContent = name;
      label.style.color = `#${color}`;
    } else {
      label.textContent = '';
    }
  }

  /// Toggle noclip fly camera: WASD + mouse look, E/Q vertical, Shift fast
  private toggleFlyMode(): void {
    if (this.flyMode) {
      this.exitFlyMode();
      return;
    }
    this.setFollowTarget(null); // re-enables orbit; we take over below
    this.flyMode = true;
    this.controls!.enabled = false;

    // Seed fly angles from the current camera orientation
    const euler = new THREE.Euler().setFromQuaternion(this.camera!.quaternion, 'YXZ');
    this.flyYaw = euler.y;
    this.flyPitch = euler.x;

    this.renderer!.domElement.requestPointerLock();

    let hud = document.getElementById('fly-hud');
    if (!hud) {
      hud = document.createElement('div');
      hud.id = 'fly-hud';
      hud.style.cssText = `
        position: fixed;
        bottom: 70px;
        left: 50%;
        transform: translateX(-50%);
        background: rgba(0, 0, 0, 0.7);
        border: 1px solid #81c784;
        border-radius: 4px;
        padding: 6px 14px;
        color: #cde;
        font-size: 13px;
        z-index: 1000;
        pointer-events: none;
      `;
      hud.innerHTML = `<span style="color:#81c784">✈ Fly mode</span>` +
        ` <span style="color:#888">WASD move · E/Q up/down · Shift fast · click to capture mouse · Esc/F exit</span>`;
      document.body.appendChild(hud);
    }
  }

  private exitFlyMode(): void {
    this.flyMode = false;
    this.flyKeys.clear();
    this.controls!.enabled = this.followTarget === null;
    if (document.pointerLockElement) document.exitPointerLock();
    document.getElementById('fly-hud')?.remove();
  }

  /// Per-frame fly movement, called from the render loop
  private updateFlyCamera(dt: number): void {
    if (!this.flyMode || !this.camera) return;

    this.camera.quaternion.setFromEuler(new THREE.Euler(this.flyPitch, this.flyYaw, 0, 'YXZ'));

    const speed = (this.flyKeys.has('ShiftLeft') || this.flyKeys.has('ShiftRight') ? 30 : 9) * dt;
    const forward = new THREE.Vector3();
    this.camera.getWorldDirection(forward);
    const right = new THREE.Vector3().crossVectors(forward, new THREE.Vector3(0, 1, 0)).normalize();

    const move = new THREE.Vector3();
    if (this.flyKeys.has('KeyW')) move.add(forward);
    if (this.flyKeys.has('KeyS')) move.sub(forward);
    if (this.flyKeys.has('KeyD')) move.add(right);
    if (this.flyKeys.has('KeyA')) move.sub(right);
    if (this.flyKeys.has('KeyE')) move.y += 1;
    if (this.flyKeys.has('KeyQ')) move.y -= 1;
    if (move.lengthSq() > 0) {
      this.camera.position.add(move.normalize().multiplyScalar(speed));
    }
  }

  private updateFollowHud(): void {
    this.updateCrosshair();
    document.getElementById('follow-hud')?.remove();
    this.canvasContainer.classList.toggle('first-person-active', !!this.followTarget);
    document.getElementById('player-hud')?.classList.toggle(
      'hidden',
      !this.followTarget || this.hudMode === 'off',
    );
    document.getElementById('broadcast-overlay')?.classList.toggle(
      'hidden',
      !this.followTarget || this.hudMode !== 'broadcast',
    );
  }

  private setHudMode(mode: HudMode, persist = true): void {
    if (!['player', 'broadcast', 'minimal', 'off'].includes(mode)) return;
    this.hudMode = mode;
    if (persist) localStorage.setItem('cs16-hud-mode', mode);
    const select = document.getElementById('hud-mode-select') as HTMLSelectElement | null;
    if (select) select.value = mode;
    const hud = document.getElementById('player-hud');
    if (hud) {
      hud.dataset.mode = mode;
      hud.classList.toggle('hidden', !this.followTarget || mode === 'off');
    }
    document.getElementById('broadcast-overlay')?.classList.toggle(
      'hidden',
      !this.followTarget || mode !== 'broadcast',
    );
    this.hudLastSignature = '';
    this.updateCrosshair();
    if (this.timeline) this.updatePlayback();
  }

  private setPlaybackMode(mode: PlaybackMode, persist = true): void {
    this.playbackMode = mode;
    if (persist) localStorage.setItem('cs16-playback-mode', mode);
    const select = document.getElementById('playback-mode-select') as HTMLSelectElement | null;
    if (select) select.value = mode;
    this.smoothedEye = null;
    this.smoothedForward = null;
    this.cameraSmoothWallTime = performance.now();
    for (const mesh of this.playerMeshes.values()) {
      mesh.traverse((object) => {
        object.userData.animName = undefined;
        object.userData.transitionFrom = undefined;
      });
    }
    if (this.timeline) this.updatePlayback();
    this.showAnnouncement(
      mode === 'cinematic' ? 'Cinematic smoothing' : 'Authentic replay',
      mode === 'cinematic' ? '#88dcff' : '#dde5f0',
    );
  }

  private setRenderQuality(quality: RenderQuality, persist = true): void {
    this.renderQuality = quality;
    if (persist) localStorage.setItem('cs16-render-quality', quality);
    const select = document.getElementById('quality-select') as HTMLSelectElement | null;
    if (select) select.value = quality;
    const ratio = quality === 'performance'
      ? Math.min(window.devicePixelRatio, 0.67)
      : Math.min(window.devicePixelRatio, quality === 'high' ? 2 : this.renderScale);
    this.renderScale = ratio;
    this.renderer?.setPixelRatio(ratio);
    if (this.renderer) {
      this.renderer.setSize(this.canvasContainer.clientWidth, this.canvasContainer.clientHeight);
    }
  }

  private cycleHudMode(): void {
    const modes: HudMode[] = ['player', 'broadcast', 'minimal', 'off'];
    const next = modes[(modes.indexOf(this.hudMode) + 1) % modes.length];
    this.setHudMode(next);
    this.showAnnouncement(`HUD · ${next[0].toUpperCase()}${next.slice(1)}`, '#b9ecff');
  }

  private buildHudTracks(): void {
    this.hudTracks.clear();
    this.inventoryCacheKey = '';
    this.inventoryCacheIds = [];
    const demo = this.timeline;
    if (!demo) return;
    for (let i = 0; i < demo.hudTimes.length; i++) {
      const kind = demo.hudKinds[i];
      const a = demo.hudA[i];
      const key = kind === 5 ? `${kind}:${a}` : String(kind);
      let track = this.hudTracks.get(key);
      if (!track) {
        track = [];
        this.hudTracks.set(key, track);
      }
      track.push({ time: demo.hudTimes[i], a, b: demo.hudB[i] });
    }
    this.hudLastSignature = '';
  }

  private hudTrackAt(kind: number, time: number, keyValue?: number): HudTrackPoint | null {
    const key = keyValue === undefined ? String(kind) : `${kind}:${keyValue}`;
    const track = this.hudTracks.get(key);
    if (!track?.length || track[0].time > time) return null;
    let lo = 0;
    let hi = track.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (track[mid].time <= time) lo = mid;
      else hi = mid - 1;
    }
    const value = track[lo];
    if (kind !== 8) {
      const reset = this.hudTrackAt(8, time);
      if (reset && reset.time > value.time) return null;
    }
    return value;
  }

  private static readonly HUD_WEAPON_NAMES: Record<number, string> = {
    1: 'P228', 2: 'Shield', 3: 'Scout', 4: 'HE Grenade', 5: 'XM1014',
    6: 'C4', 7: 'MAC-10', 8: 'AUG', 9: 'Smoke Grenade', 10: 'Elite',
    11: 'Five-SeveN', 12: 'UMP45', 13: 'SG550', 14: 'Galil', 15: 'Famas',
    16: 'USP', 17: 'Glock-18', 18: 'AWP', 19: 'MP5 Navy', 20: 'M249',
    21: 'M3', 22: 'M4A1', 23: 'TMP', 24: 'G3SG1', 25: 'Flashbang',
    26: 'Desert Eagle', 27: 'SG552', 28: 'AK-47', 29: 'Knife', 30: 'P90',
  };

  private static readonly HUD_WEAPON_ICONS: Record<number, string> = {
    1: 'p228', 2: 'shield', 3: 'scout', 4: 'hegrenade', 5: 'xm1014',
    6: 'c4', 7: 'mac10', 8: 'aug', 9: 'smokegrenade', 10: 'elite',
    11: 'fiveseven', 12: 'ump45', 13: 'sg550', 14: 'galil', 15: 'famas',
    16: 'usp', 17: 'glock18', 18: 'awp', 19: 'mp5navy', 20: 'm249',
    21: 'm3', 22: 'm4a1', 23: 'tmp', 24: 'g3sg1', 25: 'flashbang',
    26: 'deagle', 27: 'sg552', 28: 'ak47', 29: 'knife', 30: 'p90',
  };

  // Counter-Strike's fixed primary-ammo registry. WeaponList overrides this
  // when the demo carries custom definitions.
  private static readonly HUD_AMMO_BY_WEAPON: Record<number, number> = {
    1: 9, 3: 4, 5: 0, 7: 5, 8: 2, 10: 1, 11: 8, 12: 5,
    13: 2, 14: 2, 15: 2, 16: 5, 17: 1, 18: 7, 19: 1, 20: 3,
    21: 0, 22: 2, 23: 1, 24: 4, 26: 6, 27: 4, 28: 4, 30: 8,
  };

  private static readonly HUD_WEAPON_MODELS: Record<number, string> = {
    1: 'v_p228', 3: 'v_scout', 4: 'v_hegrenade', 5: 'v_xm1014',
    6: 'v_c4', 7: 'v_mac10', 8: 'v_aug', 9: 'v_smokegrenade',
    10: 'v_elite', 11: 'v_fiveseven', 12: 'v_ump45', 13: 'v_sg550',
    14: 'v_galil', 15: 'v_famas', 16: 'v_usp', 17: 'v_glock18',
    18: 'v_awp', 19: 'v_mp5', 20: 'v_m249', 21: 'v_m3',
    22: 'v_m4a1', 23: 'v_tmp', 24: 'v_g3sg1', 25: 'v_flashbang',
    26: 'v_deagle', 27: 'v_sg552', 28: 'v_ak47', 29: 'v_knife',
    30: 'v_p90',
  };

  private static weaponSlot(id: number): number {
    if ([1, 10, 11, 16, 17, 26].includes(id)) return 2;
    if (id === 29) return 3;
    if ([4, 9, 25].includes(id)) return 4;
    if (id === 6) return 5;
    return 1;
  }

  private weaponIdForModel(model: string | null): number | null {
    if (!model) return null;
    const normalized = model.replace(/^p_/, 'v_');
    const match = Object.entries(DemoPlayer.HUD_WEAPON_MODELS)
      .find(([, candidate]) => candidate === normalized);
    return match ? Number(match[0]) : null;
  }

  private povWeaponBitsAt(time: number): number {
    const demo = this.timeline;
    if (!demo?.povTimes.length || !demo.povWeaponBits.length || demo.povTimes[0] > time) return 0;
    let left = 0;
    let right = demo.povTimes.length - 1;
    while (left < right) {
      const middle = (left + right + 1) >> 1;
      if (demo.povTimes[middle] <= time) left = middle;
      else right = middle - 1;
    }
    return demo.povWeaponBits[left] ?? 0;
  }

  private reconstructedInventoryAt(name: string, time: number, activeId: number | null): number[] {
    const demo = this.timeline;
    if (!demo) return activeId ? [activeId] : [];
    const round = this.roundIndexAt(time);
    const cacheKey = `${name}|${round}|${Math.floor(time * 5)}|${activeId ?? 0}`;
    if (cacheKey === this.inventoryCacheKey) return this.inventoryCacheIds;

    const owned = new Set<number>([29]);
    const slot = demo.slot_names.indexOf(name);
    const roundStart = this.rounds[round] ?? 0;
    let previous: number | null = null;
    if (slot >= 0) {
      let start = 0;
      let end = demo.times.length;
      while (start < end) {
        const middle = (start + end) >> 1;
        if (demo.times[middle] < roundStart) start = middle + 1;
        else end = middle;
      }
      const cells = demo.slot_names.length;
      for (let index = start; index < demo.times.length && demo.times[index] <= time; index++) {
        const cell = index * cells + slot;
        if (!demo.presence[cell]) continue;
        const id = this.weaponIdForModel(this.weaponModelName(demo.weapons[cell]));
        if (!id || id === previous) continue;
        if (previous && DemoPlayer.weaponSlot(previous) === 4) owned.delete(previous);
        const ownedSlot = DemoPlayer.weaponSlot(id);
        if (ownedSlot === 1 || ownedSlot === 2) {
          for (const ownedId of owned) {
            if (DemoPlayer.weaponSlot(ownedId) === ownedSlot) owned.delete(ownedId);
          }
        }
        owned.add(id);
        previous = id;
      }
    }
    const bombFlag = this.playerBombFlagAt(name, time);
    const observedC4 = owned.has(6);
    const planted = this.bombStateAt(time).planted;
    if (bombFlag === true || (bombFlag === null && observedC4 && !planted)) owned.add(6);
    else owned.delete(6);
    if (activeId) owned.add(activeId);
    this.inventoryCacheKey = cacheKey;
    this.inventoryCacheIds = [...owned].sort((left, right) =>
      DemoPlayer.weaponSlot(left) - DemoPlayer.weaponSlot(right) || left - right);
    return this.inventoryCacheIds;
  }

  private updateWeaponInventory(
    exactPov: boolean,
    selected: PlayerState | null,
    activeId: number | null,
    hidden: boolean,
  ): number {
    const inventory = document.getElementById('hud-inventory');
    if (!inventory) return 0;
    if (hidden) {
      inventory.innerHTML = '';
      return 0;
    }

    let ids: number[] = [];
    if (exactPov) {
      const bits = this.povWeaponBitsAt(this.currentTime);
      for (let id = 1; id <= 30; id++) {
        if ((bits & (1 << id)) !== 0) ids.push(id);
      }
      if (activeId && !ids.includes(activeId)) ids.push(activeId);
      if (bits && !ids.includes(29)) ids.push(29);
      ids.sort((left, right) =>
        DemoPlayer.weaponSlot(left) - DemoPlayer.weaponSlot(right) || left - right);
    } else if (selected) {
      ids = this.reconstructedInventoryAt(selected.name, this.currentTime, activeId);
    }

    const signature = `${ids.join(',')}|${activeId ?? 0}`;
    if (inventory.dataset.signature !== signature) {
      inventory.dataset.signature = signature;
      inventory.innerHTML = ids.map((id) => {
        const name = DemoPlayer.HUD_WEAPON_NAMES[id] ?? `Weapon ${id}`;
        const icon = DemoPlayer.HUD_WEAPON_ICONS[id];
        const slot = DemoPlayer.weaponSlot(id);
        const active = id === activeId;
        const kind = slot === 4 ? 'grenade' : slot === 5 ? 'objective' : 'weapon';
        return `<span class="hud-inventory-item${active ? ' active' : ''}" data-kind="${kind}" data-slot="${slot}" `
          + `title="${this.escapeHtml(name)}${active ? ' (active)' : ''}"${active ? ' aria-current="true"' : ''}>`
          + `<span class="inventory-name">${this.escapeHtml(name.toUpperCase())}</span>`
          + `<span class="inventory-icon" aria-hidden="true"${icon
            ? ` style="--weapon-icon:url('/sprites/weapons/${icon}.png')"` : ''}></span>`
          + `<span class="inventory-slot">${slot}</span></span>`;
      }).join('');
    }
    return ids.length;
  }

  private setViewModelWeapon(weapon: string | null, hidden: boolean): void {
    const root = this.viewModel;
    if (!root) return;
    root.visible = !!this.followTarget && !hidden && !!weapon;
    if (!root.visible || !weapon || this.viewModelWeapon === weapon) return;

    const previousWeapon = this.viewModelWeapon;
    this.viewModelWeapon = weapon;
    this.viewModelEquippedAt = previousWeapon && this.isPlaying
      ? this.currentTime
      : -Infinity;
    const request = ++this.viewModelRequest;
    this.loadPlayerModelTemplate(weapon).then((template) => {
      if (!this.viewModel || request !== this.viewModelRequest || this.viewModelWeapon !== weapon) {
        return;
      }
      this.viewModel.clear();
      if (!template) {
        this.viewModel.visible = false;
        return;
      }
      const model = this.buildSkinInstance(template, 'viewWeapon');
      // v_ models are authored facing GoldSrc +X. In camera space, -Z is
      // forward. Mirror the resulting screen axis to match CS's right-handed
      // viewmodel projection instead of translating the model close to the
      // lens, which distorts the hands.
      model.rotation.y = Math.PI / 2;
      // GoldSrc viewmodels use a deliberately flatter camera-space projection
      // than world geometry. After the +90° turn, model X is camera depth;
      // compressing only that axis keeps the authored screen silhouette while
      // preventing the nearer forearm from ballooning over the weapon.
      model.scale.x = 0.72;
      model.scale.z = -1;
      model.traverse((object) => {
        if (!(object instanceof THREE.Mesh)) return;
        object.renderOrder = 1000;
        const materials = Array.isArray(object.material) ? object.material : [object.material];
        object.material = materials.map((source) => {
          const material = source.clone();
          material.depthTest = false;
          material.depthWrite = false;
          return material;
        });
      });
      this.viewModel.add(model);
    });
  }

  private animateViewModel(): void {
    const root = this.viewModel;
    if (!root?.visible) return;
    const movement = THREE.MathUtils.clamp((this.viewMotionSpeed - 20) / 230, 0, 1);
    const moving = movement > 0.04;
    const bob = moving ? Math.sin(this.currentTime * 8.5) * movement : 0;
    const sway = moving ? Math.sin(this.currentTime * 4.25) * movement : 0;
    // The authored v_ meshes are deep: the muzzle can sit about 0.2 units
    // farther from the camera than the forearms. If the root is too close,
    // perspective magnifies the near arm independently of the weapon and
    // produces the long, intersecting forearms seen on rifles such as FAMAS.
    // Pair the flattened model depth with a safe camera offset, giving
    // pistols, knives, and rifles one stable apparent hand scale.
    const reconstructedShotAt = this.followTarget && this.followTarget !== 'Spectator Camera'
      ? this.recentShotForPlayer(this.followTarget, this.currentTime)
      : null;
    const reconstructedShotAge = reconstructedShotAt === null
      ? Infinity
      : this.currentTime - reconstructedShotAt;
    // GoldSrc weapon animations provide some kick, but reconstructed HLTV
    // views do not carry the local punch-angle. A short deterministic impulse
    // restores the missing recoil without changing the authoritative aim ray.
    const recoil = reconstructedShotAge >= 0 && reconstructedShotAge < 0.18
      ? Math.sin(Math.min(1, reconstructedShotAge / 0.18) * Math.PI) * 0.012
      : 0;
    root.position.set(
      0.09 + sway * 0.0012,
      -0.09 + Math.abs(bob) * 0.0012 - recoil * 0.3,
      -0.27 + recoil,
    );
    root.rotation.set(bob * 0.0015 - recoil * 1.8, sway * 0.002, sway * 0.001 + recoil * 0.25);
    const model = root.getObjectByName('viewWeapon') as THREE.Group | undefined;
    if (!model) return;
    const recordedSample = this.followTarget === 'Spectator Camera'
      ? this.weaponAnimAt(this.currentTime)
      : null;
    const anims = model.userData.anims as import('./wasm.ts').MdlAnim[] | undefined;
    if (!anims?.length) return;

    let anim: import('./wasm.ts').MdlAnim | undefined;
    let framePosition = 0;
    let animationKey = '';
    if (recordedSample) {
      anim = anims[recordedSample.sequence];
      if (anim?.frames) {
        framePosition = Math.min(
          Math.max(0, this.currentTime - recordedSample.time) * anim.fps,
          anim.frames - 1,
        );
        animationKey = `recorded:${recordedSample.sequence}`;
      }
    } else {
      const shotAt = reconstructedShotAt;
      const action = this.followTarget
        ? this.recentViewModelAction(this.followTarget, this.currentTime)
        : null;
      const shotAnim = anims.find((candidate) =>
        candidate.frames > 0 && /shoot|fire|attack/i.test(candidate.name));
      const actionAnim = action ? anims.find((candidate) => candidate.frames > 0 && (
        action.kind === 'reload' ? /reload|clip|bolt|pump/i.test(candidate.name)
          : action.kind === 'silencer' ? /silenc/i.test(candidate.name)
            : /throw|gren|attack|shoot/i.test(candidate.name)
      )) : undefined;
      const drawAnim = anims.find((candidate) =>
        candidate.frames > 0 && /draw|deploy|up/i.test(candidate.name));
      const idleAnim = anims.find((candidate) =>
        candidate.frames > 0 && /idle/i.test(candidate.name))
        ?? anims.find((candidate) => candidate.frames > 0);
      const shotAge = shotAt === null ? Infinity : this.currentTime - shotAt;
      const shotDuration = shotAnim ? shotAnim.frames / Math.max(1, shotAnim.fps) : 0;
      const equipAge = this.currentTime - this.viewModelEquippedAt;
      const drawDuration = drawAnim ? drawAnim.frames / Math.max(1, drawAnim.fps) : 0;
      const actionAge = action ? this.currentTime - action.time : Infinity;
      const actionDuration = actionAnim ? actionAnim.frames / Math.max(1, actionAnim.fps) : 0;
      if (actionAnim && actionAge >= 0 && actionAge <= actionDuration) {
        anim = actionAnim;
        framePosition = Math.min(actionAge * anim.fps, anim.frames - 1);
        animationKey = `reconstructed-${action!.kind}:${action!.time}`;
      } else if (shotAnim && shotAge >= 0 && shotAge <= shotDuration) {
        anim = shotAnim;
        framePosition = Math.min(shotAge * anim.fps, anim.frames - 1);
        animationKey = `reconstructed-shot:${shotAt}`;
      } else if (drawAnim && equipAge >= 0 && equipAge <= drawDuration) {
        anim = drawAnim;
        framePosition = Math.min(equipAge * anim.fps, anim.frames - 1);
        animationKey = `reconstructed-draw:${this.viewModelEquippedAt}`;
      } else if (idleAnim) {
        anim = idleAnim;
        framePosition = (this.currentTime * anim.fps) % anim.frames;
        animationKey = 'reconstructed-idle';
      }
    }
    if (!anim || anim.frames <= 0 || anim.data.length === 0) {
      this.tickSkinAnimation(model, moving);
      return;
    }
    const frame = Math.floor(framePosition);
    const looping = animationKey === 'reconstructed-idle';
    const nextFrame = looping
      ? (frame + 1) % anim.frames
      : Math.min(anim.frames - 1, frame + 1);
    const mix = this.playbackMode === 'cinematic' ? framePosition - frame : 0;
    const key = `${animationKey}:${framePosition.toFixed(2)}:${this.playbackMode}`;
    if (model.userData.frame === key) return;
    model.userData.frame = key;
    const mesh = model.getObjectByName('skinMesh') as THREE.Mesh | undefined;
    const attribute = mesh?.geometry.getAttribute('position') as THREE.BufferAttribute | undefined;
    if (!attribute) return;
    const values = attribute.array.length;
    const offset = frame * values;
    const nextOffset = nextFrame * values;
    if (offset + values > anim.data.length || nextOffset + values > anim.data.length) return;
    const output = attribute.array as Float32Array;
    for (let i = 0; i < values; i++) {
      output[i] = anim.data[offset + i]
        + (anim.data[nextOffset + i] - anim.data[offset + i]) * mix;
    }
    attribute.needsUpdate = true;
  }

  private recentShotForPlayer(name: string, time: number): number | null {
    const demo = this.timeline;
    const player = this.players.find((candidate) => candidate.name === name);
    if (!demo?.shotTimes.length || !player) return null;
    let left = 0;
    let right = demo.shotTimes.length - 1;
    if (demo.shotTimes[0] > time) return null;
    while (left < right) {
      const mid = (left + right + 1) >> 1;
      if (demo.shotTimes[mid] <= time) left = mid;
      else right = mid - 1;
    }
    for (let index = left; index >= 0 && time - demo.shotTimes[index] <= 1.5; index--) {
      if (demo.shotSlots[index] === player.index) return demo.shotTimes[index];
    }
    return null;
  }

  private recentViewModelAction(
    name: string,
    time: number,
  ): { time: number; kind: 'reload' | 'throw' | 'silencer' } | null {
    const demo = this.timeline;
    const player = this.players.find((candidate) => candidate.name === name);
    if (!demo?.network_sounds.length || !player) return null;
    let left = 0;
    let right = demo.network_sounds.length - 1;
    if (demo.network_sounds[0].time > time) return null;
    while (left < right) {
      const middle = (left + right + 1) >> 1;
      if (demo.network_sounds[middle].time <= time) left = middle;
      else right = middle - 1;
    }
    for (let index = left; index >= 0; index--) {
      const sound = demo.network_sounds[index];
      if (time - sound.time > 2.4) break;
      if (sound.entity !== 0 && sound.entity !== player.index + 1) continue;
      const sample = sound.sample.toLowerCase();
      if (/silencer_(on|off)|silence[dr]/.test(sample)) return { time: sound.time, kind: 'silencer' };
      if (/pinpull|gren_cock|throw/.test(sample)) return { time: sound.time, kind: 'throw' };
      if (/clip(out|in)|reload|bolt|pump/.test(sample)) return { time: sound.time, kind: 'reload' };
    }
    return null;
  }

  private weaponAnimAt(time: number): { time: number; sequence: number; body: number } | null {
    const demo = this.timeline;
    if (!demo?.weaponAnimTimes.length || demo.weaponAnimTimes[0] > time) return null;
    let lo = 0;
    let hi = demo.weaponAnimTimes.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (demo.weaponAnimTimes[mid] <= time) lo = mid;
      else hi = mid - 1;
    }
    return {
      time: demo.weaponAnimTimes[lo],
      sequence: demo.weaponAnimSequences[lo],
      body: demo.weaponAnimBodies[lo],
    };
  }

  private displayWeaponName(name: string): string {
    return name
      .replace(/^models\/p_/, '')
      .replace(/^p_/, '')
      .replace(/^weapon_/, '')
      .replace(/\.mdl$/, '')
      .replace(/glock18/i, 'Glock-18')
      .replace(/fiveseven/i, 'Five-SeveN')
      .replace(/deagle/i, 'Desert Eagle')
      .replace(/mp5navy/i, 'MP5 Navy')
      .replace(/_/g, ' ')
      .toUpperCase();
  }

  private updateRadar(states: PlayerState[], selected: PlayerState | null): void {
    const dots = document.getElementById('hud-radar-dots');
    if (!dots) return;
    dots.parentElement?.classList.toggle('unavailable', !selected || this.hudMode !== 'player');
    if (!selected || this.hudMode !== 'player') {
      dots.innerHTML = '';
      return;
    }
    const selectedTeam = this.teamAt(selected.name, this.currentTime);
    const yaw = THREE.MathUtils.degToRad(selected.angles.y);
    const forwardX = Math.cos(yaw);
    const forwardY = Math.sin(yaw);
    const rightX = -forwardY;
    const rightY = forwardX;
    const radarRadius = 56;
    const worldRadius = 2600;
    const html: string[] = [];

    for (const state of states) {
      if (state.name === selected.name) continue;
      const team = this.teamAt(state.name, this.currentTime);
      if (selectedTeam && team && team !== selectedTeam) continue;
      const dx = state.origin.x - selected.origin.x;
      const dy = state.origin.y - selected.origin.y;
      let x = (dx * rightX + dy * rightY) / worldRadius * radarRadius;
      let y = -(dx * forwardX + dy * forwardY) / worldRadius * radarRadius;
      const distance = Math.hypot(x, y);
      if (distance > radarRadius) {
        x *= radarRadius / distance;
        y *= radarRadius / distance;
      }
      const color = team === 'CT' ? '#59c9f5' : team === 'T' ? '#ffd45a' : '#aeb9c5';
      html.push(
        `<span class="hud-radar-dot" title="${this.escapeHtml(state.name)}" ` +
        `style="--dot-x:${x.toFixed(1)}px;--dot-y:${y.toFixed(1)}px;--dot-color:${color}"></span>`,
      );
    }
    dots.innerHTML = html.join('');
  }

  private updatePlayerHud(states: PlayerState[]): void {
    const hud = document.getElementById('player-hud');
    if (!hud) return;
    const visible = !!this.followTarget && this.hudMode !== 'off';
    hud.classList.toggle('hidden', !visible);
    if (!visible) return;
    hud.dataset.mode = this.hudMode;

    const exactPov = this.followTarget === 'Spectator Camera';
    const selected = exactPov
      ? null
      : states.find((state) => state.name === this.followTarget) ?? null;
    const recorderHealth = exactPov ? this.hudTrackAt(1, this.currentTime)?.a ?? null : null;
    const health = recorderHealth ?? (
      selected && (selected.health ?? -1) >= 0 ? selected.health! : null
    );
    const armor = exactPov ? this.hudTrackAt(2, this.currentTime)?.a ?? null : null;
    const money = exactPov ? this.hudTrackAt(3, this.currentTime)?.a ?? null : null;
    const activeWeapon = exactPov ? this.hudTrackAt(4, this.currentTime) : null;
    const weaponDef = activeWeapon
      ? this.timeline?.hud_weapons.find((weapon) => weapon.id === activeWeapon.a)
      : null;
    const entityWeapon = selected ? this.weaponModelName(selected.weapon ?? 0) : null;
    const activeWeaponId = activeWeapon?.a ?? this.weaponIdForModel(entityWeapon);
    const weaponName = activeWeapon
      ? DemoPlayer.HUD_WEAPON_NAMES[activeWeapon.a]
        ?? this.displayWeaponName(weaponDef?.name ?? `Weapon ${activeWeapon.a}`)
      : entityWeapon
        ? this.displayWeaponName(entityWeapon)
        : null;
    const clip = activeWeapon && activeWeapon.b >= 0 ? activeWeapon.b : null;
    const ammoId = weaponDef?.ammo_id ?? (
      activeWeapon ? DemoPlayer.HUD_AMMO_BY_WEAPON[activeWeapon.a] : undefined
    );
    const reserve = ammoId !== undefined && ammoId >= 0
      ? this.hudTrackAt(5, this.currentTime, ammoId)?.b ?? null
      : null;
    const fovValue = exactPov ? this.hudTrackAt(7, this.currentTime)?.a ?? 90 : 90;
    const fov = fovValue === 0 ? 90 : fovValue;
    const hideFlags = exactPov ? this.hudTrackAt(6, this.currentTime)?.a ?? 0 : 0;
    const hideAll = (hideFlags & 4) !== 0;
    const hideWeapons = hideAll || (hideFlags & 1) !== 0;
    const hideHealth = hideAll || (hideFlags & 8) !== 0;
    const hideMoney = hideAll || (hideFlags & 32) !== 0;
    const viewModelWeapon = exactPov
      ? activeWeapon ? DemoPlayer.HUD_WEAPON_MODELS[activeWeapon.a] ?? null : null
      : selected ? this.weaponFor(selected.name, selected.weapon).replace(/^p_/, 'v_') : null;
    this.setViewModelWeapon(
      viewModelWeapon,
      hideWeapons || this.hudMode === 'off' || (exactPov && fov < 80),
    );

    const setValue = (id: string, value: string | number | null, hidden = false) => {
      const element = document.getElementById(id);
      if (!element) return;
      element.textContent = value === null ? '' : String(value);
      element.parentElement?.classList.toggle('unavailable', value === null || hidden);
    };
    setValue('hud-health', health, hideHealth);
    setValue('hud-armor', armor, hideHealth);
    setValue('hud-money', money === null ? null : `$${money.toLocaleString()}`, hideMoney);
    setValue('hud-clip', clip, hideWeapons);
    setValue('hud-reserve', reserve, hideWeapons);
    const inventoryCount = this.updateWeaponInventory(
      exactPov,
      selected,
      activeWeaponId,
      hideWeapons,
    );
    document.querySelector('#player-hud .hud-ammo')?.classList.toggle(
      'unavailable',
      hideWeapons || (clip === null && reserve === null),
    );
    document.querySelector('#player-hud .hud-current-weapon')?.classList.toggle(
      'unavailable',
      hideWeapons || (clip === null && reserve === null),
    );
    document.querySelector('#player-hud .hud-weapon')?.classList.toggle(
      'unavailable',
      hideWeapons || (inventoryCount === 0 && weaponName === null && clip === null && reserve === null),
    );

    const observer = exactPov ? this.observerSampleAt(this.currentTime) : null;
    const target = document.getElementById('hud-target-name');
    if (target) target.textContent = observer?.name ?? this.followTarget ?? '';
    const source = document.getElementById('hud-source');
    if (source) {
      source.textContent = exactPov
        ? `RECORDED POV${observer?.modeLabel ? ` · ${observer.modeLabel}` : ''}`
        : 'RECONSTRUCTED POV';
      source.title = exactPov
        ? 'Full-rate camera and HUD data recorded in the demo.'
        : 'Camera reconstructed from server-observed entity position and angles.';
    }
    const team = this.followTarget && !exactPov
      ? this.teamAt(this.followTarget, this.currentTime)
      : null;
    hud.dataset.team = team === 'T' ? 't' : 'ct';
    hud.classList.toggle('scoped', this.hudMode === 'player' && fov < 80);
    document.getElementById('fp-crosshair')?.classList.toggle(
      'hidden',
      exactPov && this.hudMode === 'player' && fov < 80,
    );
    this.updateActionProgress(states, selected, exactPov);
    this.updateBroadcastOverlay(states, this.computeDeaths(this.currentTime));

    const verticalFov = this.goldSrcFovToVertical(fov);
    if (this.camera && exactPov && Math.abs(this.camera.fov - verticalFov) > 0.01) {
      this.camera.fov = verticalFov;
      this.camera.updateProjectionMatrix();
    }

    const signature = [
      this.followTarget, this.hudMode, health, armor, money, weaponName, clip, reserve,
      fov, hideFlags, Math.floor(this.currentTime * 5),
    ].join('|');
    if (signature !== this.hudLastSignature) {
      this.hudLastSignature = signature;
      this.updateRadar(states, selected);
    }
  }

  private updateBroadcastOverlay(states: PlayerState[], deaths: Map<string, number>): void {
    const overlay = document.getElementById('broadcast-overlay');
    if (!overlay) return;
    const visible = !!this.followTarget && this.hudMode === 'broadcast';
    overlay.classList.toggle('hidden', !visible);
    if (!visible || !this.timeline) return;
    const renderKey = `${Math.floor(this.currentTime * 4)}|${this.followTarget}|${[...deaths.keys()].sort().join(',')}`;
    if (overlay.dataset.signature === renderKey) return;
    overlay.dataset.signature = renderKey;

    const byName = new Map(states.map((state) => [state.name, state]));
    const losses = { CT: 0, T: 0 };
    for (const event of this.timeline.events) {
      if (event.time > this.currentTime || event.event_type !== 'RoundEnd') continue;
      const winner = /CT|COUNTER/i.test(event.data.winner ?? '') ? 'CT'
        : /TERROR|^T$/i.test(event.data.winner ?? '') ? 'T' : null;
      if (!winner) continue;
      losses[winner] = 0;
      losses[winner === 'CT' ? 'T' : 'CT']++;
    }
    const lossMoney = (streak: number) => Math.min(3400, 1400 + Math.max(0, streak - 1) * 500);
    const priceOf = (id: number) => {
      const name = (DemoPlayer.HUD_WEAPON_ICONS[id] ?? '').toLowerCase();
      return DemoPlayer.EQUIPMENT_PRICES[name] ?? 0;
    };
    const renderSide = (team: 'CT' | 'T') => {
      const members = this.players
        .filter((player) => this.teamAt(player.name, this.currentTime) === team)
        .sort((left, right) => left.index - right.index)
        .slice(0, 5);
      let equipment = 0;
      let utility = 0;
      const cards = members.map((player) => {
        const state = byName.get(player.name);
        const activeId = state ? this.weaponIdForModel(this.weaponModelName(state.weapon ?? 0)) : null;
        const inventory = this.reconstructedInventoryAt(player.name, this.currentTime, activeId);
        const grenades = inventory.filter((id) => DemoPlayer.weaponSlot(id) === 4).length;
        const value = inventory.reduce((total, id) => total + priceOf(id), 0);
        equipment += value;
        utility += grenades;
        const dead = deaths.has(player.name);
        const health = dead ? '—' : state?.health != null ? Math.max(0, state.health) : '?';
        const weapon = activeId ? (DemoPlayer.HUD_WEAPON_NAMES[activeId] ?? '—') : '—';
        return `<article class="broadcast-card${dead ? ' dead' : ''}${this.followTarget === player.name ? ' following' : ''}">`
          + `<strong>${this.escapeHtml(player.name)}</strong><span class="broadcast-card-meta">`
          + `<em>${health} HP</em><span>${this.escapeHtml(weapon)} · ${grenades}U</span></span></article>`;
      }).join('');
      const node = document.getElementById(`broadcast-${team.toLowerCase()}`);
      if (node) node.innerHTML = `<div class="broadcast-side-head"><span>${team === 'CT' ? 'COUNTER-TERRORISTS' : 'TERRORISTS'}`
        + ` · $${equipment.toLocaleString()}</span><span>${utility} UTIL · LOSS +$${lossMoney(losses[team]).toLocaleString()}</span></div>`
        + `<div class="broadcast-lineup">${cards}</div>`;
    };
    renderSide('CT');
    renderSide('T');

    const roundStart = this.rounds[this.roundIndexAt(this.currentTime)] ?? 0;
    const kills = this.timeline.events.filter((event) =>
      event.event_type === 'Kill' && event.time >= roundStart && event.time <= this.currentTime,
    );
    const aliveCt = this.players.filter((player) =>
      this.teamAt(player.name, this.currentTime) === 'CT' && !deaths.has(player.name)).length;
    const aliveT = this.players.filter((player) =>
      this.teamAt(player.name, this.currentTime) === 'T' && !deaths.has(player.name)).length;
    let callout = aliveCt === 1 && aliveT >= 2 ? `CLUTCH · CT 1v${aliveT}`
      : aliveT === 1 && aliveCt >= 2 ? `CLUTCH · T 1v${aliveCt}` : '';
    const recent = kills[kills.length - 1];
    if (!callout && recent?.data.killer && this.currentTime - recent.time <= 4) {
      const count = kills.filter((event) => event.data.killer === recent.data.killer).length;
      if (count >= 2) callout = `${count}K · ${recent.data.killer}`;
    }
    const roundEnd = [...this.timeline.events].reverse().find((event) =>
      event.event_type === 'RoundEnd' && event.time <= this.currentTime && event.time >= roundStart,
    );
    if (roundEnd && this.currentTime - roundEnd.time <= 5 && kills.length) {
      const totals = new Map<string, number>();
      for (const kill of kills) if (kill.data.killer) totals.set(kill.data.killer, (totals.get(kill.data.killer) ?? 0) + 1);
      const best = [...totals].sort((left, right) => right[1] - left[1])[0];
      if (best) callout = `PLAYER OF THE ROUND · ${best[0]} · ${best[1]}K`;
    }
    const calloutNode = document.getElementById('broadcast-callout');
    if (calloutNode) {
      calloutNode.textContent = callout;
      calloutNode.classList.toggle('hidden', !callout);
    }
  }

  private bombStateAt(time: number): { planted: boolean; plantedAt: number | null } {
    let planted = false;
    let plantedAt: number | null = null;
    for (const event of this.timeline?.events ?? []) {
      if (event.time > time) break;
      if (event.event_type === 'BombPlanted') {
        planted = true;
        plantedAt = event.time;
      } else if (
        event.event_type === 'BombDefused'
        || event.event_type === 'BombExploded'
        || event.event_type === 'RoundStart'
        || event.event_type === 'RoundEnd'
      ) {
        planted = false;
        plantedAt = null;
      }
    }
    return { planted, plantedAt };
  }

  private playerBombFlagAt(name: string, time: number): boolean | null {
    const demo = this.timeline;
    const player = this.players.find((candidate) => candidate.name === name);
    let flags: number | null = null;
    // ScoreAttrib flags describe transient round state (dead, bomb, VIP).
    // Some historical HLTV streams do not send an explicit zero for every
    // player at spawn, so never carry a previous round's last value forward.
    const roundStart = this.rounds[this.roundIndexAt(time)] ?? 0;
    const currentRoundCutoff = Math.max(0, roundStart - 0.5);
    if (demo && player) {
      for (const update of demo.player_stats) {
        if (update.time > time) break;
        if (
          update.time >= currentRoundCutoff
          && update.slot === player.index
          && update.flags != null
        ) {
          flags = update.flags;
        }
      }
    }
    return flags === null ? null : (flags & 2) !== 0;
  }

  private playerHasBombAt(name: string, time: number, state?: PlayerState | null): boolean {
    const flag = this.playerBombFlagAt(name, time);
    if (flag !== null) return flag;
    return !!state && this.weaponModelName(state.weapon ?? 0) === 'p_c4';
  }

  private c4PositionAt(time: number): Vec3 | null {
    const demo = this.timeline;
    if (!demo?.objTimes.length || demo.objTimes[0] > time) return null;
    let left = 0;
    let right = demo.objTimes.length - 1;
    while (left < right) {
      const mid = (left + right + 1) >> 1;
      if (demo.objTimes[mid] <= time) left = mid;
      else right = mid - 1;
    }
    for (let index = left; index >= 0 && time - demo.objTimes[index] <= 0.6; index--) {
      if (demo.objKinds[index] !== 4) continue;
      const offset = index * 3;
      return {
        x: demo.objPositions[offset],
        y: demo.objPositions[offset + 1],
        z: demo.objPositions[offset + 2],
      };
    }
    return null;
  }

  private updateActionProgress(
    states: PlayerState[],
    selected: PlayerState | null,
    exactPov: boolean,
  ): void {
    const panel = document.getElementById('hud-action-progress');
    const fill = document.getElementById('hud-action-fill');
    const label = document.getElementById('hud-action-label');
    const percentLabel = document.getElementById('hud-action-percent');
    if (!panel || !fill || !label || !percentLabel || !this.timeline) return;

    let action: 'plant' | 'defuse' | null = null;
    let progress = 0;
    const bomb = this.bombStateAt(this.currentTime);

    if (exactPov) {
      const bar = this.hudTrackAt(11, this.currentTime);
      const activeWeapon = this.hudTrackAt(4, this.currentTime)?.a ?? 0;
      if (bar && bar.a > 0 && (bomb.planted || activeWeapon === 6)) {
        const age = this.currentTime - bar.time;
        if (age >= 0 && age <= bar.a) {
          const start = THREE.MathUtils.clamp(bar.b, 0, 100);
          progress = start + age / bar.a * (100 - start);
          action = bomb.planted ? 'defuse' : 'plant';
        }
      }
    } else if (selected && this.followTarget) {
      const team = this.teamAt(selected.name, this.currentTime);
      if (team === 'T' && this.playerHasBombAt(selected.name, this.currentTime, selected)) {
        const completion = this.timeline.events.find((event) =>
          event.event_type === 'BombPlanted'
          && event.time >= this.currentTime
          && event.time <= this.currentTime + 3.05,
        );
        if (completion) {
          action = 'plant';
          progress = (this.currentTime - (completion.time - 3)) / 3 * 100;
        }
      } else if (team === 'CT' && bomb.planted) {
        const completion = this.timeline.events.find((event) =>
          event.event_type === 'BombDefused'
          && event.time >= this.currentTime
          && event.time <= this.currentTime + 10.05,
        );
        const c4 = this.c4PositionAt(this.currentTime);
        if (completion && c4) {
          const deaths = this.computeDeaths(this.currentTime);
          const livingCts = states.filter((state) =>
            !deaths.has(state.name)
            && this.teamAt(state.name, this.currentTime) === 'CT');
          const distanceToBomb = (state: PlayerState) => Math.hypot(
            state.origin.x - c4.x,
            state.origin.y - c4.y,
            state.origin.z - c4.z,
          );
          const closest = livingCts.sort((leftState, rightState) =>
            distanceToBomb(leftState) - distanceToBomb(rightState))[0];
          if (closest?.name === selected.name && distanceToBomb(selected) <= 100) {
            const tenSecondStart = completion.time - 10;
            const startC4 = this.c4PositionAt(tenSecondStart);
            const startState = interpolateSoa(this.timeline, tenSecondStart, 'authentic')
              .find((state) => state.name === selected.name);
            const inRangeAtTen = !!startC4 && !!startState && Math.hypot(
              startState.origin.x - startC4.x,
              startState.origin.y - startC4.y,
              startState.origin.z - startC4.z,
            ) <= 100;
            const duration = inRangeAtTen ? 10 : 5;
            const startedAt = completion.time - duration;
            if (this.currentTime >= startedAt) {
              action = 'defuse';
              progress = (this.currentTime - startedAt) / duration * 100;
            }
          }
        }
      }
    }

    if (!action || progress < 0 || progress > 101) {
      panel.classList.add('hidden');
      panel.setAttribute('aria-valuenow', '0');
      return;
    }
    const rounded = Math.round(THREE.MathUtils.clamp(progress, 0, 100));
    panel.classList.remove('hidden');
    panel.dataset.action = action;
    panel.setAttribute('aria-valuenow', String(rounded));
    label.textContent = action === 'plant' ? 'PLANTING C4' : 'DEFUSING BOMB';
    percentLabel.textContent = `${rounded}%`;
    fill.style.width = `${rounded}%`;
  }

  private updateRecordedScreenFade(): void {
    let overlay = document.getElementById('recorded-fade-overlay');
    const recorded = this.followTarget === 'Spectator Camera';
    const sample = recorded ? this.hudTrackAt(9, this.currentTime) : null;
    if (!sample) {
      overlay?.remove();
      return;
    }
    const packedTiming = sample.a >>> 0;
    const duration = (packedTiming & 0xffff) / 4096;
    const hold = (packedTiming >>> 16) / 4096;
    const age = this.currentTime - sample.time;
    const flags = this.hudTrackAt(10, this.currentTime)?.a ?? 0;
    const fadeOut = (flags & 0x0001) !== 0;
    const stayOut = (flags & 0x0004) !== 0;
    let phase = 0;
    if (age >= 0) {
      if (fadeOut) {
        phase = duration > 0 ? Math.min(1, age / duration) : 1;
        if (!stayOut && age > duration + hold) phase = 0;
      } else if (age <= hold) {
        phase = 1;
      } else {
        phase = duration > 0 ? Math.max(0, 1 - (age - hold) / duration) : 0;
      }
    }
    if (phase <= 0.001) {
      overlay?.remove();
      return;
    }
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.id = 'recorded-fade-overlay';
      overlay.style.cssText = `
        position: absolute; inset: 0; z-index: 979;
        pointer-events: none;
      `;
      this.canvasContainer.appendChild(overlay);
    }
    const rgba = sample.b >>> 0;
    const red = rgba & 0xff;
    const green = (rgba >>> 8) & 0xff;
    const blue = (rgba >>> 16) & 0xff;
    const alpha = ((rgba >>> 24) & 0xff) / 255 * phase;
    overlay.style.background = `rgba(${red}, ${green}, ${blue}, ${alpha.toFixed(4)})`;
  }

  private escapeHtml(s: string): string {
    const div = document.createElement('div');
    div.textContent = s;
    return div.innerHTML;
  }

  private observerSampleAt(time: number): {
    target: number;
    mode: number;
    name: string | null;
    modeLabel: string | null;
  } | null {
    const demo = this.timeline;
    if (!demo?.observerTimes.length) return null;
    let lo = 0;
    let hi = demo.observerTimes.length - 1;
    if (demo.observerTimes[0] > time) return null;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (demo.observerTimes[mid] <= time) lo = mid;
      else hi = mid - 1;
    }
    const target = demo.observerTargets[lo];
    const mode = demo.observerModes[lo];
    const player = target > 0
      ? this.players.find((candidate) => candidate.index === target - 1)
        ?? this.players.find((candidate) => candidate.name === demo.slot_names[target - 1])
      : null;
    const modeLabel = ({
      1: 'CHASE',
      2: 'CHASE FREE',
      3: 'ROAMING',
      4: 'IN-EYE',
      5: 'MAP',
      6: 'MAP CHASE',
    } as Record<number, string>)[mode] ?? null;
    return { target, mode, name: player?.name ?? null, modeLabel };
  }

  /// Full-rate recorder camera sample for POV demos (lerped between frames)
  private povSampleAt(time: number): { origin: Vec3; angles: Vec3 } | null {
    const d = this.timeline;
    if (!d || d.povTimes.length === 0) return null;
    const n = d.povTimes.length;
    let left = 0;
    let right = n - 1;
    while (left < right) {
      const mid = (left + right + 1) >> 1;
      if (d.povTimes[mid] <= time) left = mid;
      else right = mid - 1;
    }
    const j = Math.min(left + 1, n - 1);
    const t0 = d.povTimes[left];
    const t1 = d.povTimes[j];
    const t = j > left && t1 > t0 ? Math.max(0, Math.min(1, (time - t0) / (t1 - t0))) : 0;
    const a = left * 6;
    const b = j * 6;
    const lerp = (x: number, y: number) => x + (y - x) * t;
    const lerpAng = (x: number, y: number) => {
      const dd = ((y - x) % 360 + 540) % 360 - 180;
      return x + dd * t;
    };
    return {
      origin: {
        x: lerp(d.povData[a], d.povData[b]),
        y: lerp(d.povData[a + 1], d.povData[b + 1]),
        z: lerp(d.povData[a + 2], d.povData[b + 2]),
      },
      angles: {
        x: lerpAng(d.povData[a + 3], d.povData[b + 3]),
        y: lerpAng(d.povData[a + 4], d.povData[b + 4]),
        z: 0,
      },
    };
  }

  private updateFollowCamera(
    states: Map<string, PlayerState>,
    deaths?: Map<string, number>,
  ): void {
    if (!this.followTarget || !this.camera) return;
    if (this.followTarget !== 'Spectator Camera' && deaths?.has(this.followTarget)) {
      return;
    }
    // The recorder's own view has an exact full-rate track — use it directly
    const povState = this.followTarget === 'Spectator Camera'
      ? this.povSampleAt(this.currentTime)
      : null;
    const state = povState || states.get(this.followTarget);
    if (!state) return; // target not in view (dead/removed): keep last camera

    const SCALE = 0.01;
    const pos = new THREE.Vector3(
      state.origin.x * SCALE,
      state.origin.z * SCALE,
      -state.origin.y * SCALE
    );

    const yaw = THREE.MathUtils.degToRad(state.angles.y);
    // Entity pitch is the MODEL tilt: -view_pitch/3 (GoldSrc convention,
    // verified against the recorder's ClientData track). The POV track
    // carries true view pitch directly.
    let pitchDeg = ((state.angles.x % 360) + 540) % 360 - 180;
    if (!povState) {
      pitchDeg = THREE.MathUtils.clamp(-3 * pitchDeg, -89, 89);
    }
    const pitch = THREE.MathUtils.degToRad(pitchDeg);
    // GoldSrc view direction mapped to Three.js (see coordinate conversion above);
    // positive GoldSrc pitch looks down, hence -sin(pitch) on Y
    const forward = new THREE.Vector3(
      Math.cos(pitch) * Math.cos(yaw),
      -Math.sin(pitch),
      -Math.cos(pitch) * Math.sin(yaw)
    );

    // Player entity origin is the center of the standing hull; GoldSrc's
    // standing view_ofs is 28 units above it and 12 while ducking. The
    // recorder POV track already contains its final vieworg.
    const EYE = this.followTarget === 'Spectator Camera'
      ? 0
      : ((state as PlayerState).ducking ? 12 : 28) * SCALE;
    const eye = pos.add(new THREE.Vector3(0, EYE, 0));
    const motionDt = this.currentTime - this.viewMotionTime;
    if (this.viewMotionPosition && motionDt > 0 && motionDt < 0.5) {
      this.viewMotionSpeed = this.viewMotionPosition.distanceTo(eye) / motionDt / SCALE;
    } else if (!povState && (state as PlayerState).velocity) {
      const velocity = (state as PlayerState).velocity!;
      this.viewMotionSpeed = Math.hypot(velocity.x, velocity.y);
    } else {
      this.viewMotionSpeed = 0;
    }
    this.viewMotionPosition = eye.clone();
    this.viewMotionTime = this.currentTime;
    let cameraEye = eye;
    let cameraForward = forward;
    if (this.playbackMode === 'cinematic') {
      const now = performance.now();
      const dt = Math.min(0.05, Math.max(0, (now - this.cameraSmoothWallTime) / 1000));
      this.cameraSmoothWallTime = now;
      if (!this.smoothedEye || this.smoothedEye.distanceTo(eye) > 6) {
        this.smoothedEye = eye.clone();
      } else {
        // A critically damped positional follow removes packet micro-jitter.
        // Orientation remains authoritative so the crosshair never drifts
        // away from the recorded aim vector.
        const alpha = 1 - Math.exp(-28 * dt);
        this.smoothedEye.lerp(eye, alpha);
      }
      cameraEye = this.smoothedEye;
      if (!povState) {
        if (!this.smoothedForward || this.smoothedForward.dot(forward) < 0.25) {
          this.smoothedForward = forward.clone();
        } else {
          // Entity view angles in old HLTV recordings arrive in small packet
          // steps. Smooth only reconstructed aim, with a short time constant
          // that removes the steps without making the camera feel detached.
          const aimAlpha = 1 - Math.exp(-36 * dt);
          this.smoothedForward.lerp(forward, aimAlpha).normalize();
        }
        cameraForward = this.smoothedForward;
      } else {
        this.smoothedForward = forward.clone();
      }
    } else {
      this.smoothedEye = eye.clone();
      this.smoothedForward = forward.clone();
      this.cameraSmoothWallTime = performance.now();
    }
    this.camera.position.copy(cameraEye);
    this.camera.lookAt(cameraEye.clone().add(cameraForward));
    this.updateAimLabel();
  }

  /// Build round start times and the per-player model-change history from events
  private buildRoundsAndModels(): void {
    this.rounds = [0];
    this.modelTimeline.clear();
    this.teamTimeline.clear();
    for (const event of this.timeline?.events ?? []) {
      // The parser canonicalizes recorder-local ResetHUD and full RoundTime
      // signals into one live RoundStart per round.
      if (event.event_type === 'RoundStart') {
        if (event.time - this.rounds[this.rounds.length - 1] > 15) {
          this.rounds.push(event.time);
        }
      } else if (event.event_type === 'ModelChange' && event.data.player && event.data.model) {
        let list = this.modelTimeline.get(event.data.player);
        if (!list) {
          list = [];
          this.modelTimeline.set(event.data.player, list);
        }
        list.push([event.time, event.data.model]);
      }
    }
    const demo = this.timeline;
    if (!demo) return;
    for (const update of demo.player_stats) {
      if (!update.team) continue;
      const team = /CT|COUNTER/i.test(update.team)
        ? 'CT'
        : /TERROR/i.test(update.team) ? 'T' : null;
      const name = this.players.find((player) => player.index === update.slot)?.name
        ?? demo.slot_names[update.slot];
      if (!team || !name) continue;
      let list = this.teamTimeline.get(name);
      if (!list) {
        list = [];
        this.teamTimeline.set(name, list);
      }
      list.push([update.time, team]);
    }
  }

  private roundIndexAt(time: number): number {
    let idx = 0;
    for (let i = 0; i < this.rounds.length; i++) {
      if (this.rounds[i] <= time) idx = i;
      else break;
    }
    return idx;
  }

  private seekToRound(index: number): void {
    if (!this.rounds.length) return;
    const clamped = Math.max(0, Math.min(this.rounds.length - 1, index));
    this.seekTo(this.rounds[clamped] / this.duration);
  }

  private updateRoundIndicator(): void {
    const el = document.getElementById('round-indicator');
    if (el && this.rounds.length > 1) {
      el.textContent = `R${this.roundIndexAt(this.currentTime) + 1}/${this.rounds.length}`;
    }
  }

  /// Render round-start ticks and kill dots onto the seek bar
  private renderTimelineMarkers(): void {
    this.timelineEl.querySelectorAll('.timeline-marker-round, .timeline-marker-kill')
      .forEach((el) => el.remove());
    if (!this.timeline || this.duration <= 0) return;

    for (const t of this.rounds.slice(1)) {
      const tick = document.createElement('div');
      tick.className = 'timeline-marker-round';
      tick.style.left = `${(t / this.duration) * 100}%`;
      this.timelineEl.appendChild(tick);
    }
    for (const event of this.timeline.events) {
      if (event.event_type !== 'Kill') continue;
      const dot = document.createElement('div');
      dot.className = 'timeline-marker-kill';
      dot.style.left = `${(event.time / this.duration) * 100}%`;
      this.timelineEl.appendChild(dot);
    }
  }

  private toggleEventNavigator(force?: boolean): void {
    const panel = document.getElementById('event-navigator');
    if (!panel) return;
    const show = force ?? panel.classList.contains('hidden');
    panel.classList.toggle('hidden', !show);
    if (show) this.renderEventNavigator(
      panel.querySelector<HTMLButtonElement>('.event-nav-tabs .active')?.dataset.view ?? 'rounds',
    );
  }

  private renderEventNavigator(view: string): void {
    const list = document.getElementById('event-nav-list');
    const demo = this.timeline;
    if (!list || !demo) return;
    document.querySelectorAll<HTMLButtonElement>('.event-nav-tabs button').forEach((button) => {
      button.classList.toggle('active', button.dataset.view === view);
    });
    if (view === 'rounds') {
      list.innerHTML = this.rounds.map((start, index) => {
        const end = Math.min(this.rounds[index + 1] ?? this.duration, this.duration);
        const events = demo.events.filter((event) => event.time >= start && event.time < end);
        const kills = events.filter((event) => event.event_type === 'Kill').length;
        const result = [...events].reverse().find((event) => event.event_type === 'RoundEnd');
        const planted = events.some((event) => event.event_type === 'BombPlanted');
        const defused = events.some((event) => event.event_type === 'BombDefused');
        const exploded = events.some((event) => event.event_type === 'BombExploded');
        const winner = result?.data.winner;
        const economy = this.equipmentValueAt(Math.min(end, start + 3));
        const outcome = exploded ? 'exploded' : defused ? 'defused' : planted ? 'planted' : '';
        return `<button class="nav-event" type="button" data-time="${start}">
          <time>${this.formatTime(start)}</time>
          <span class="nav-event-copy"><strong>Round ${index + 1}</strong>
          <small>${this.formatTime(end - start)} · ${kills} kills${outcome ? ` · C4 ${outcome}` : ''}
          · $${Math.round(economy.ct / 100) * 100}/$${Math.round(economy.t / 100) * 100}</small></span>
          <span class="nav-event-tag">${winner ? `${winner} WIN` : 'PLAY'}</span>
        </button>`;
      }).join('');
      return;
    }

    const highlights: Array<{ event: GameEvent; label: string; detail: string; tag: string }> = [];
    const seenHighlights = new Set<string>();
    for (let i = 0; i < demo.events.length; i++) {
      const event = demo.events[i];
      const semanticKey = [
        event.event_type,
        Math.round(event.time * 4),
        event.data.killer ?? '',
        event.data.victim ?? '',
        this.roundIndexAt(event.time),
      ].join('|');
      if (seenHighlights.has(semanticKey)) continue;
      seenHighlights.add(semanticKey);
      if (event.event_type === 'Kill' && event.data.killer && event.data.victim) {
        let streak = 1;
        for (let j = i - 1; j >= 0; j--) {
          const previous = demo.events[j];
          if (event.time - previous.time > 6) break;
          if (previous.event_type === 'Kill' && previous.data.killer === event.data.killer) streak++;
        }
        highlights.push({
          event,
          label: `${event.data.killer} → ${event.data.victim}`,
          detail: `${event.data.weapon ?? 'weapon'}${event.data.headshot ? ' · headshot' : ''}`,
          tag: streak > 1 ? `${streak}K` : 'KILL',
        });
      } else if (['BombPlanted', 'BombDefused', 'BombExploded'].includes(event.event_type)) {
        highlights.push({
          event,
          label: event.event_type.replace(/([a-z])([A-Z])/g, '$1 $2'),
          detail: `Round ${this.roundIndexAt(event.time) + 1}`,
          tag: 'C4',
        });
      }
    }
    list.innerHTML = highlights.map(({ event, label, detail, tag }) =>
      `<button class="nav-event" type="button" data-time="${Math.max(0, event.time - 3)}"
        ${event.data.killer ? `data-follow="${this.escapeHtml(event.data.killer)}"` : ''}>
        <time>${this.formatTime(event.time)}</time>
        <span class="nav-event-copy"><strong>${this.escapeHtml(label)}</strong>
        <small>${this.escapeHtml(detail)}</small></span>
        <span class="nav-event-tag">${tag}</span>
      </button>`
    ).join('');
  }

  private static readonly EQUIPMENT_PRICES: Record<string, number> = {
    knife: 0, c4: 0, usp: 500, glock18: 400, p228: 600, deagle: 650,
    fiveseven: 750, elite: 800, mp5: 1500, tmp: 1250, mac10: 1400,
    ump45: 1700, p90: 2350, galil: 2000, famas: 2250, ak47: 2500,
    m4a1: 3100, scout: 2750, aug: 3500, sg552: 3500, awp: 4750,
    g3sg1: 5000, sg550: 4200, m3: 1700, xm1014: 3000, m249: 5750,
    hegrenade: 300, flashbang: 200, smokegrenade: 300,
  };

  private equipmentValueAt(time: number): { ct: number; t: number } {
    const total = { ct: 0, t: 0 };
    if (!this.timeline) return total;
    for (const state of interpolateSoa(this.timeline, time, 'authentic')) {
      const model = this.modelAt(state.name, time);
      const team = DemoPlayer.teamOfModel(model);
      const weapon = this.weaponFor(state.name, state.weapon)
        .replace(/^p_/, '').replace(/^w_/, '').toLowerCase();
      const value = DemoPlayer.EQUIPMENT_PRICES[weapon] ?? 0;
      if (team === 'CT') total.ct += value;
      else if (team === 'T') total.t += value;
    }
    return total;
  }

  private toggleStudio(force?: boolean): void {
    const panel = document.getElementById('studio-panel');
    if (!panel) return;
    const visible = force ?? panel.classList.contains('hidden');
    panel.classList.toggle('hidden', !visible);
    document.getElementById('studio-btn')?.classList.toggle('active', visible);
    if (visible) this.renderBookmarks();
  }

  private setStudioStatus(message: string): void {
    const status = document.getElementById('studio-status');
    if (status) status.textContent = message;
  }

  private toggleDirector(force?: boolean): void {
    this.directorEnabled = force ?? !this.directorEnabled;
    this.directorLastSwitch = -Infinity;
    document.getElementById('director-btn')?.classList.toggle('active', this.directorEnabled);
    document.getElementById('director-badge')?.classList.toggle('hidden', !this.directorEnabled);
    this.setStudioStatus(this.directorEnabled
      ? 'Director follows fights, clutches and bomb action.'
      : 'Manual camera control restored.');
    if (this.directorEnabled && this.timeline) this.updateDirector(true);
  }

  private updateDirector(force = false): void {
    const demo = this.timeline;
    if (!this.directorEnabled || !demo || this.killReplayState) return;
    if (!force && this.currentTime - this.directorLastSwitch < 2.4) return;
    const upcoming = demo.events.find((event) =>
      event.event_type === 'Kill'
      && !!event.data.killer
      && event.time >= this.currentTime - 0.4
      && event.time <= this.currentTime + 6,
    );
    let target = upcoming?.data.killer ?? null;
    if (!target && this.bombPlantedAt !== null) {
      const deaths = this.computeDeaths(this.currentTime);
      target = this.players.find((player) => !deaths.has(player.name))?.name ?? null;
    }
    if (!target) {
      const states = interpolateSoa(demo, this.currentTime, 'authentic');
      target = states.find((state) => !this.computeDeaths(this.currentTime).has(state.name))?.name ?? null;
    }
    if (target && target !== this.followTarget) {
      this.directorLastSwitch = this.currentTime;
      this.setFollowTarget(target);
      const badge = document.getElementById('director-badge');
      if (badge) badge.textContent = `AUTO DIRECTOR · ${target}`;
    }
  }

  private startKillReplay(): void {
    const demo = this.timeline;
    if (!demo) return;
    const recent = [...demo.events].reverse().find((event) =>
      event.event_type === 'Kill' && !!event.data.killer
      && event.time <= this.currentTime && event.time >= this.currentTime - 10,
    );
    const event = recent ?? demo.events.find((item) =>
      item.event_type === 'Kill' && !!item.data.killer && item.time > this.currentTime,
    );
    if (!event?.data.killer) {
      this.setStudioStatus('No kill is available near this point.');
      return;
    }
    this.killReplayState = {
      returnTime: Math.max(this.currentTime, event.time + 2),
      returnTarget: this.followTarget,
      returnSpeed: this.playbackSpeed,
      eventTime: event.time,
    };
    this.playbackSpeed = 0.5;
    this.speedSelect.value = '0.5';
    this.setFollowTarget(event.data.killer);
    this.seekToTime(Math.max(0, event.time - 4));
    if (!this.isPlaying) this.togglePlayback();
    this.setStudioStatus(`Replaying ${event.data.killer}'s kill at 0.5×.`);
  }

  private finishKillReplayIfNeeded(): void {
    const replay = this.killReplayState;
    if (!replay || this.currentTime < replay.eventTime + 2) return;
    this.killReplayState = null;
    this.playbackSpeed = replay.returnSpeed;
    this.speedSelect.value = String(replay.returnSpeed);
    this.setFollowTarget(replay.returnTarget);
    this.seekToTime(replay.returnTime);
    this.setStudioStatus('Returned to the original match position.');
  }

  private toggleTacticalMap(): void {
    this.tacticalVisible = !this.tacticalVisible;
    document.getElementById('tactical-btn')?.classList.toggle('active', this.tacticalVisible);
    document.getElementById('tactical-map')?.classList.toggle('hidden', !this.tacticalVisible);
    if (this.tacticalVisible) this.renderTacticalMap();
  }

  private toggleEconomy(): void {
    this.economyVisible = !this.economyVisible;
    document.getElementById('economy-btn')?.classList.toggle('active', this.economyVisible);
    document.getElementById('economy-strip')?.classList.toggle('hidden', !this.economyVisible);
    this.updateEconomyStrip();
  }

  private updateEconomyStrip(): void {
    if (!this.economyVisible) return;
    const value = this.equipmentValueAt(this.currentTime);
    const ct = document.querySelector<HTMLElement>('#economy-strip .ct');
    const t = document.querySelector<HTMLElement>('#economy-strip .t');
    if (ct) ct.textContent = `CT EQUIPMENT $${value.ct.toLocaleString()}`;
    if (t) t.textContent = `T EQUIPMENT $${value.t.toLocaleString()}`;
  }

  private updateTacticalTracks(states: PlayerState[]): void {
    if (!this.tacticalVisible || this.currentTime - this.tacticalLastSample < 0.2) return;
    if (this.currentTime < this.tacticalLastSample) this.playerTrails.clear();
    this.tacticalLastSample = this.currentTime;
    for (const state of states) {
      let trail = this.playerTrails.get(state.name);
      if (!trail) {
        trail = [];
        this.playerTrails.set(state.name, trail);
      }
      trail.push({ time: this.currentTime, x: state.origin.x, y: state.origin.y });
      while (trail.length && trail[0].time < this.currentTime - 12) trail.shift();
    }
    this.renderTacticalMap(states);
  }

  private renderTacticalMap(currentStates?: PlayerState[]): void {
    const canvas = document.getElementById('tactical-map') as HTMLCanvasElement | null;
    const demo = this.timeline;
    if (!canvas || !demo || !this.tacticalVisible) return;
    const context = canvas.getContext('2d');
    if (!context) return;
    const states = currentStates ?? interpolateSoa(demo, this.currentTime, 'authentic');
    const points = states.map((state) => ({ x: state.origin.x, y: state.origin.y }));
    for (const trail of this.playerTrails.values()) points.push(...trail);
    if (!points.length) return;
    let minX = Math.min(...points.map((point) => point.x));
    let maxX = Math.max(...points.map((point) => point.x));
    let minY = Math.min(...points.map((point) => point.y));
    let maxY = Math.max(...points.map((point) => point.y));
    const span = Math.max(maxX - minX, maxY - minY, 900);
    const centerX = (minX + maxX) / 2;
    const centerY = (minY + maxY) / 2;
    minX = centerX - span * 0.58; maxX = centerX + span * 0.58;
    minY = centerY - span * 0.35; maxY = centerY + span * 0.35;
    const project = (x: number, y: number) => ({
      x: 24 + (x - minX) / (maxX - minX) * (canvas.width - 48),
      y: canvas.height - 24 - (y - minY) / (maxY - minY) * (canvas.height - 48),
    });
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.fillStyle = '#07101d';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.strokeStyle = 'rgba(105,150,185,.10)';
    context.lineWidth = 1;
    for (let x = 0; x <= canvas.width; x += 64) {
      context.beginPath(); context.moveTo(x, 0); context.lineTo(x, canvas.height); context.stroke();
    }
    for (let y = 0; y <= canvas.height; y += 64) {
      context.beginPath(); context.moveTo(0, y); context.lineTo(canvas.width, y); context.stroke();
    }
    for (const [name, trail] of this.playerTrails) {
      if (trail.length < 2) continue;
      const team = this.teamAt(name, this.currentTime);
      context.strokeStyle = team === 'CT' ? 'rgba(79,195,247,.34)' : 'rgba(255,213,79,.32)';
      context.lineWidth = 2;
      context.beginPath();
      trail.forEach((point, index) => {
        const screen = project(point.x, point.y);
        if (index === 0) context.moveTo(screen.x, screen.y);
        else context.lineTo(screen.x, screen.y);
      });
      context.stroke();
    }
    const deaths = this.computeDeaths(this.currentTime);
    for (const state of states) {
      const screen = project(state.origin.x, state.origin.y);
      const team = this.teamAt(state.name, this.currentTime);
      context.fillStyle = deaths.has(state.name)
        ? '#566171'
        : team === 'CT' ? '#55c9f7' : team === 'T' ? '#ffd45a' : '#d6dce5';
      context.beginPath(); context.arc(screen.x, screen.y, state.name === this.followTarget ? 7 : 5, 0, Math.PI * 2); context.fill();
      context.fillStyle = '#cbd7e3';
      context.font = '16px system-ui';
      context.fillText(state.name.slice(0, 15), screen.x + 9, screen.y + 5);
    }
    const seenEntities = new Set<number>();
    for (let i = demo.objTimes.length - 1; i >= 0; i--) {
      if (demo.objTimes[i] < this.currentTime - 0.3) break;
      if (demo.objTimes[i] > this.currentTime + 0.05 || seenEntities.has(demo.objEnts[i])) continue;
      seenEntities.add(demo.objEnts[i]);
      const point = project(demo.objPositions[i * 3], demo.objPositions[i * 3 + 1]);
      const kind = demo.objKinds[i];
      context.fillStyle = kind === 4 ? '#ff6b6b' : kind === 3 ? '#aeb8c4' : kind === 2 ? '#f4f4ff' : '#ff9e4a';
      context.fillRect(point.x - 3, point.y - 3, 6, 6);
    }
    context.fillStyle = '#5e7187';
    context.font = '700 14px monospace';
    context.fillText(`${this.mapDisplayName(this.mapName).toUpperCase()} · 12S TRAILS`, 18, 22);
  }

  private bookmarkStorageKey(): string {
    return `cs16-bookmarks:${this.demoIdentity || this.mapName || 'demo'}`;
  }

  private loadBookmarks(): void {
    try {
      const value = JSON.parse(localStorage.getItem(this.bookmarkStorageKey()) ?? '[]');
      this.bookmarks = Array.isArray(value) ? value : [];
    } catch {
      this.bookmarks = [];
    }
    this.renderBookmarks();
  }

  private addBookmark(): void {
    if (!this.timeline) return;
    const nearby = [...this.timeline.events].reverse().find((event) =>
      event.time <= this.currentTime + 1 && event.time >= this.currentTime - 4
      && ['Kill', 'BombPlanted', 'BombDefused', 'BombExploded'].includes(event.event_type),
    );
    const label = nearby?.event_type === 'Kill'
      ? `${nearby.data.killer ?? '?'} → ${nearby.data.victim ?? '?'}`
      : nearby?.event_type.replace(/([a-z])([A-Z])/g, '$1 $2')
        ?? `Round ${this.roundIndexAt(this.currentTime) + 1}`;
    this.bookmarks.push({
      id: `${Date.now()}-${Math.round(this.currentTime * 1000)}`,
      time: this.currentTime,
      label,
      follow: this.followTarget,
    });
    this.bookmarks.sort((a, b) => a.time - b.time);
    localStorage.setItem(this.bookmarkStorageKey(), JSON.stringify(this.bookmarks));
    this.renderBookmarks();
    this.setStudioStatus(`Bookmarked ${this.formatTime(this.currentTime)}.`);
  }

  private renderBookmarks(): void {
    const list = document.getElementById('bookmark-list');
    if (!list) return;
    list.innerHTML = this.bookmarks.length
      ? this.bookmarks.map((bookmark) => `<div class="bookmark-row" data-id="${bookmark.id}">
          <time>${this.formatTime(bookmark.time)}</time>
          <span>${this.escapeHtml(bookmark.label)}</span>
          <button type="button" aria-label="Delete bookmark">×</button>
        </div>`).join('')
      : '<div class="diagnostics-empty">No saved moments yet.</div>';
  }

  private async copyShareLink(): Promise<void> {
    const params = new URLSearchParams({
      demo: this.demoIdentity,
      t: this.currentTime.toFixed(3),
    });
    if (this.followTarget) params.set('follow', this.followTarget);
    const url = `${location.origin}${location.pathname}#${params.toString()}`;
    try {
      await navigator.clipboard.writeText(url);
      this.setStudioStatus('Timestamp link copied to clipboard.');
    } catch {
      window.prompt('Copy this replay link:', url);
    }
  }

  private downloadBlob(blob: Blob, filename: string): void {
    const anchor = document.createElement('a');
    anchor.href = URL.createObjectURL(blob);
    anchor.download = filename;
    anchor.click();
    window.setTimeout(() => URL.revokeObjectURL(anchor.href), 1000);
  }

  private captureScreenshot(): void {
    if (!this.renderer || !this.scene || !this.camera) return;
    this.renderer.render(this.scene, this.camera);
    this.renderer.domElement.toBlob((blob) => {
      if (!blob) {
        this.setStudioStatus('Screenshot capture is unavailable in this browser.');
        return;
      }
      this.downloadBlob(blob, `${this.mapName}-${this.formatTime(this.currentTime).replace(':', '-')}.png`);
      this.setStudioStatus('Screenshot saved.');
    }, 'image/png');
  }

  private recordClip(): void {
    if (this.clipRecording || !this.renderer || typeof MediaRecorder === 'undefined') return;
    const canvas = this.renderer.domElement;
    const stream = canvas.captureStream(60);
    const chunks: Blob[] = [];
    const recorder = new MediaRecorder(stream, { mimeType: 'video/webm' });
    this.clipRecording = true;
    document.getElementById('clip-btn')?.classList.add('active');
    recorder.ondataavailable = (event) => { if (event.data.size) chunks.push(event.data); };
    recorder.onstop = () => {
      this.clipRecording = false;
      document.getElementById('clip-btn')?.classList.remove('active');
      stream.getTracks().forEach((track) => track.stop());
      if (chunks.length) this.downloadBlob(
        new Blob(chunks, { type: 'video/webm' }),
        `${this.mapName}-${this.formatTime(this.currentTime).replace(':', '-')}.webm`,
      );
      this.setStudioStatus('Eight-second WebM clip saved.');
    };
    recorder.start(250);
    if (!this.isPlaying) this.togglePlayback();
    this.setStudioStatus('Recording the next eight seconds…');
    window.setTimeout(() => { if (recorder.state !== 'inactive') recorder.stop(); }, 8000);
  }

  private applySharedLocation(): void {
    if (this.sharedLocationApplied || !location.hash || !this.timeline) return;
    const params = new URLSearchParams(location.hash.slice(1));
    if (params.get('demo') && params.get('demo') !== this.demoIdentity) return;
    const time = Number(params.get('t'));
    if (Number.isFinite(time)) this.seekToTime(time);
    const follow = params.get('follow');
    if (follow && this.timeline.slot_names.includes(follow)) this.setFollowTarget(follow);
    this.sharedLocationApplied = true;
  }

  private replayPrevious(seconds = 10): void {
    if (!this.timeline) return;
    this.seekToTime(this.currentTime - seconds);
    if (!this.isPlaying) this.togglePlayback();
  }

  /// Authentic TAB-style scoreboard. ScoreInfo/TeamInfo/ScoreAttrib are used
  /// when present; event-derived values fill gaps in older POV recordings.
  private toggleStats(): void {
    const existing = document.getElementById('stats-panel');
    if (existing) {
      existing.remove();
      return;
    }
    if (!this.timeline) return;

    const panel = document.createElement('div');
    panel.id = 'stats-panel';
    document.body.appendChild(panel);
    this.renderStatsPanel();
  }

  private renderStatsPanel(): void {
    const panel = document.getElementById('stats-panel');
    const demo = this.timeline;
    if (!panel || !demo) return;
    type Row = { kills: number; deaths: number; hs: number; team: string; flags: number };
    const stats = new Map<string, Row>();
    const roundStart = this.rounds[this.roundIndexAt(this.currentTime)] ?? 0;
    const currentRoundCutoff = Math.max(0, roundStart - 0.5);
    const row = (name: string): Row => {
      let value = stats.get(name);
      if (!value) {
        const team = this.teamAt(name, this.currentTime) ?? '';
        value = { kills: 0, deaths: 0, hs: 0, team, flags: 0 };
        stats.set(name, value);
      }
      return value;
    };
    for (const player of this.players) row(player.name);
    const authoritative = new Set<string>();
    for (const update of demo.player_stats) {
      if (update.time > this.currentTime) break;
      const name = this.players.find((player) => player.index === update.slot)?.name
        ?? demo.slot_names[update.slot];
      if (!name) continue;
      const value = row(name);
      if (update.frags != null) {
        value.kills = update.frags;
        authoritative.add(name);
      }
      if (update.deaths != null) value.deaths = update.deaths;
      if (update.team) value.team = /CT|COUNTER/i.test(update.team) ? 'CT' : /TERROR/i.test(update.team) ? 'T' : update.team;
      if (update.flags != null && update.time >= currentRoundCutoff) {
        value.flags = update.flags;
      }
    }
    for (const event of demo.events) {
      if (event.time > this.currentTime) break;
      if (event.event_type === 'Kill') {
        if (event.data.killer) {
          if (!authoritative.has(event.data.killer)) row(event.data.killer).kills++;
          if (event.data.headshot) row(event.data.killer).hs++;
        }
        if (event.data.victim && !authoritative.has(event.data.victim)) row(event.data.victim).deaths++;
      } else if (event.event_type === 'Suicide' && event.data.victim && !authoritative.has(event.data.victim)) {
        row(event.data.victim).deaths++;
      }
    }
    const deaths = this.computeDeaths(this.currentTime);
    const states = new Map(interpolateSoa(demo, this.currentTime).map((state) => [state.name, state]));
    const renderTeam = (team: 'CT' | 'T', label: string) => {
      const rows = [...stats.entries()]
        .filter(([name, value]) => value.team === team
          || (!value.team && (this.teamAt(name, this.currentTime) ?? '') === team))
        .sort((a, b) => b[1].kills - a[1].kills || a[1].deaths - b[1].deaths)
        .map(([name, value]) => {
          const state = states.get(name);
          const weapon = state ? this.weaponFor(name, state.weapon).replace(/^p_/, '').toUpperCase() : '—';
          const dead = deaths.has(name) || !!(value.flags & 1);
          const bomb = !!(value.flags & 2);
          return `<tr class="${dead ? 'score-dead' : ''}">
            <td><span class="score-life">${dead ? '×' : '●'}</span>${this.escapeHtml(name)}${bomb ? ' <b class="score-bomb">C4</b>' : ''}</td>
            <td class="score-equip">${this.escapeHtml(weapon)}</td>
            <td>${value.kills}</td><td>${value.deaths}</td><td>${Math.min(value.hs, Math.max(0, value.kills))}</td>
            <td>${value.deaths ? (value.kills / value.deaths).toFixed(2) : value.kills.toFixed(2)}</td>
          </tr>`;
        }).join('');
      return `<section class="score-section ${team.toLowerCase()}">
        <header><span>${label}</span><small>${rows ? `${(rows.match(/<tr/g) ?? []).length} PLAYERS` : 'NO DATA'}</small></header>
        <table><thead><tr><th>PLAYER</th><th>EQUIPMENT</th><th>K</th><th>D</th><th>HS</th><th>K/D</th></tr></thead>
        <tbody>${rows}</tbody></table></section>`;
    };
    panel.innerHTML = `<div class="score-panel-head">
      <div><small>LIVE SCOREBOARD</small><strong>${this.formatTime(this.currentTime)}</strong></div>
      <span>ROUND ${this.roundIndexAt(this.currentTime) + 1} · TAB TO CLOSE</span>
    </div>${renderTeam('CT', 'COUNTER-TERRORISTS')}${renderTeam('T', 'TERRORISTS')}`;
  }

  /// Jump to the next kill and watch it through the killer's eyes
  private killCam(): void {
    if (!this.timeline) return;
    const next = this.timeline.events.find(
      (e) => e.event_type === 'Kill' && e.data.killer && e.time > this.currentTime + 0.5
    );
    if (!next) return;
    this.setFollowTarget(next.data.killer!);
    this.seekToTime(next.time - 3);
    if (!this.isPlaying) this.togglePlayback();
  }

  private switchAfterFollowedDeath(killer: string, victim: string): void {
    if (this.followTarget !== victim || !this.timeline) return;
    const deaths = this.computeDeaths(this.currentTime);
    const victimTeam = this.teamAt(victim, this.currentTime) ?? this.preferredFollowTeam;
    // Staying with the selected side is less disorienting than immediately
    // jumping to the opponent who landed the final bullet.
    let next = this.players.find((player) =>
      player.name !== victim
      && !deaths.has(player.name)
      && this.teamAt(player.name, this.currentTime) === victimTeam,
    )?.name ?? null;
    const killerAvailable = killer && killer !== victim && !deaths.has(killer)
      && this.timeline.slot_names.includes(killer);
    if (!next && killerAvailable) next = killer;
    if (!next) {
      next = this.players.find((player) => !deaths.has(player.name))?.name ?? null;
    }
    this.setFollowTarget(next);
    this.showAnnouncement(
      next ? `Death view · ${next}` : 'Round over · free camera',
      '#ff9b77',
    );
  }

  private static readonly OBJ_MODELS: Record<number, string> = {
    1: 'w_hegrenade', 2: 'w_flashbang', 3: 'w_smokegrenade', 4: 'w_c4', 5: 'w_backpack',
    10: 'w_ak47', 11: 'w_m4a1', 12: 'w_awp', 13: 'w_deagle', 14: 'w_mp5', 15: 'w_usp',
    16: 'w_glock18', 17: 'w_famas', 18: 'w_galil', 19: 'w_sg552', 20: 'w_aug', 21: 'w_scout',
    22: 'w_elite', 23: 'w_fiveseven', 24: 'w_g3sg1', 25: 'w_m249', 26: 'w_m3',
    27: 'w_mac10', 28: 'w_p228', 29: 'w_p90', 30: 'w_sg550', 31: 'w_tmp',
    32: 'w_ump45', 33: 'w_xm1014', 34: 'w_knife', 35: 'w_shield',
    36: 'w_assault', 37: 'w_kevlar', 38: 'w_thighpack',
  };

  /// Render grenades/C4 near the current time; fire effects on detonation
  private updateObjects(): void {
    const d = this.timeline;
    if (!d?.objTimes?.length || !this.scene) return;
    const SCALE = 0.01;
    const t = this.currentTime;

    type ObjectPoint = { time: number; kind: number; x: number; y: number; z: number };
    type ObjectBracket = { previous?: ObjectPoint; next?: ObjectPoint };

    // Find the authoritative samples on either side of demo time for each
    // entity. Object samples are stored globally by time, so a short window
    // keeps this proportional to the number of live objects rather than the
    // full match.
    let lo = 0;
    let hi = d.objTimes.length;
    while (lo < hi) {
      const middle = (lo + hi) >> 1;
      if (d.objTimes[middle] < t - 0.25) lo = middle + 1;
      else hi = middle;
    }
    const brackets = new Map<number, ObjectBracket>();
    for (let i = lo; i < d.objTimes.length && d.objTimes[i] <= t + 0.25; i++) {
      const b = i * 3;
      const point: ObjectPoint = {
        time: d.objTimes[i],
        kind: d.objKinds[i],
        x: d.objPositions[b] * SCALE,
        y: d.objPositions[b + 2] * SCALE,
        z: -d.objPositions[b + 1] * SCALE,
      };
      const ent = d.objEnts[i];
      const bracket = brackets.get(ent) ?? {};
      if (point.time <= t) bracket.previous = point;
      else if (!bracket.next) bracket.next = point;
      brackets.set(ent, bracket);
    }

    const current = new Map<number, {
      kind: number; x: number; y: number; z: number; moving: boolean;
    }>();
    for (const [ent, bracket] of brackets) {
      const previous = bracket.previous;
      if (!previous || t - previous.time > 0.2) continue;
      const next = bracket.next;
      const canInterpolate = !!next
        && next.kind === previous.kind
        && next.time > previous.time
        && next.time - previous.time <= 0.25;
      const alpha = canInterpolate
        ? THREE.MathUtils.clamp((t - previous.time) / (next!.time - previous.time), 0, 1)
        : 0;
      const lerp = (from: number, to: number) => from + (to - from) * alpha;
      const movement = canInterpolate
        ? Math.hypot(next!.x - previous.x, next!.y - previous.y, next!.z - previous.z)
        : 0;
      current.set(ent, {
        kind: previous.kind,
        x: lerp(previous.x, next?.x ?? previous.x),
        y: lerp(previous.y, next?.y ?? previous.y),
        z: lerp(previous.z, next?.z ?? previous.z),
        moving: movement > 0.015,
      });
    }

    for (const [ent, s] of current) {
      let obj = this.objectMeshes.get(ent);
      if (obj && obj.kind !== s.kind) {
        this.scene.remove(obj.group);
        this.objectMeshes.delete(ent);
        obj = undefined;
      }
      if (!obj) {
        const group = new THREE.Group();
        group.visible = false;
        this.scene.add(group);
        obj = { group, kind: s.kind, lastSeen: t };
        this.objectMeshes.set(ent, obj);
        this.loadPlayerModelTemplate(DemoPlayer.OBJ_MODELS[s.kind]).then((tpl) => {
          if (tpl && this.objectMeshes.get(ent)?.group === group) {
            group.add(this.buildSkinInstance(tpl, 'objSkin'));
            group.visible = true;
          }
        });
      }
      // Smoke grenades detonate when they come to rest (the entity persists
      // while emitting, unlike HE/flash which vanish on detonation)
      if (obj.kind === 3 && !obj.detonated) {
        const moved = obj.group.position.distanceTo(new THREE.Vector3(s.x, s.y, s.z));
        if (!s.moving && moved < 0.02 && obj.lastSeen < t) {
          if (obj.stillSince === undefined) obj.stillSince = t;
          if (t - obj.stillSince > 0.55) {
            obj.detonated = true;
            if (!d.temp_effects.length) {
              this.spawnDetonation(3, new THREE.Vector3(s.x, s.y, s.z));
            }
          }
        } else if (moved >= 0.02) {
          obj.stillSince = undefined;
        }
      }
      obj.group.position.set(s.x, s.y, s.z);
      if (s.kind <= 3) {
        // Demo entities do not transmit a useful grenade orientation. Apply a
        // stable, continuous tumble instead of changing pose at sample edges.
        const phase = (ent % 17) * 0.37;
        obj.group.rotation.set(t * 5.3 + phase, t * 4.1, t * 3.7 + phase * 0.5);
      }
      obj.lastSeen = t;
    }

    // Departed objects: detonation effects for grenades, cleanup for the rest
    for (const [ent, obj] of this.objectMeshes) {
      if (current.has(ent)) continue;
      const gone = t - obj.lastSeen;
      if (!d.temp_effects.length && gone > 0 && gone < 0.6 && obj.kind >= 1 && obj.kind <= 2) {
        this.spawnDetonation(obj.kind, obj.group.position.clone());
      }
      if (gone > 0.3 || gone < -0.3) {
        this.scene.remove(obj.group);
        this.objectMeshes.delete(ent);
      }
    }
  }

  private getSmokeTexture(): THREE.CanvasTexture {
    if (this.smokeTexture) return this.smokeTexture;
    const canvas = document.createElement('canvas');
    canvas.width = 128;
    canvas.height = 128;
    const context = canvas.getContext('2d')!;
    const gradient = context.createRadialGradient(64, 64, 4, 64, 64, 62);
    gradient.addColorStop(0, 'rgba(255,255,255,0.92)');
    gradient.addColorStop(0.28, 'rgba(245,247,249,0.72)');
    gradient.addColorStop(0.62, 'rgba(210,216,222,0.34)');
    gradient.addColorStop(1, 'rgba(185,193,201,0)');
    context.fillStyle = gradient;
    context.fillRect(0, 0, 128, 128);
    this.smokeTexture = new THREE.CanvasTexture(canvas);
    this.smokeTexture.colorSpace = THREE.SRGBColorSpace;
    return this.smokeTexture;
  }

  private spawnDetonation(kind: number, pos: THREE.Vector3, bornT = this.currentTime): void {
    if (!this.scene) return;
    if (kind === 3) {
      // Smoke: a billowing cluster of puffs (deterministic per detonation)
      let seed = (Math.abs(Math.round(pos.x * 73 + pos.z * 179)) % 9973) + 1;
      const rand = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
      const group = new THREE.Group();
      group.position.copy(pos).add(new THREE.Vector3(0, 0.25, 0));
      for (let i = 0; i < 11; i++) {
        const shade = 0.62 + rand() * 0.16;
        const puff = new THREE.Sprite(
          new THREE.SpriteMaterial({
            map: this.getSmokeTexture(),
            color: new THREE.Color(shade, shade + 0.01, shade + 0.03),
            transparent: true,
            opacity: 0.0,
            depthWrite: false,
            depthTest: true,
          })
        );
        const theta = rand() * Math.PI * 2;
        const r = 0.25 + rand() * 0.75;
        puff.userData.dir = new THREE.Vector3(
          Math.cos(theta) * r,
          0.15 + rand() * 0.55,
          Math.sin(theta) * r
        );
        puff.userData.size = 0.4 + rand() * 0.45;
        puff.userData.phase = rand() * Math.PI * 2;
        puff.userData.baseOpacity = 0.34 + rand() * 0.14;
        group.add(puff);
      }
      this.scene.add(group);
      this.addEffect({ mesh: group, bornT, ttl: 13, kind });
      return;
    }
    // HE: orange flash; flashbang: white flash
    const color = kind === 1 ? 0xffa030 : 0xffffff;
    const mesh = new THREE.Mesh(
      new THREE.SphereGeometry(0.7, 14, 10),
      new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9, depthWrite: false })
    );
    mesh.position.copy(pos);
    this.scene.add(mesh);
    this.addEffect({ mesh, bornT, ttl: 0.45, kind });

    // Flashbang exposure depends on distance, view direction, and map
    // occlusion. This remains reconstructed for HLTV tracks, but avoids
    // blinding a camera through several solid walls.
    if (kind === 2 && this.camera) {
      const toFlash = pos.clone().sub(this.camera.position);
      const distance = toFlash.length();
      const direction = toFlash.clone().normalize();
      const facing = THREE.MathUtils.clamp(
        (this.camera.getWorldDirection(new THREE.Vector3()).dot(direction) + 0.25) / 1.25,
        0,
        1,
      );
      const distanceFactor = THREE.MathUtils.clamp(1 - distance / 14, 0, 1);
      const ray = new THREE.Raycaster(
        this.camera.position,
        direction,
        0.05,
        Math.max(0.05, distance - 0.08),
      );
      const occluded = !!this.mapMesh && ray.intersectObject(this.mapMesh, true).length > 0;
      const exposure = occluded ? 0 : distanceFactor * (0.22 + facing * 0.78);
      if (exposure < 0.04) return;
      let overlay = document.getElementById('flash-overlay');
      if (!overlay) {
        overlay = document.createElement('div');
        overlay.id = 'flash-overlay';
        overlay.style.cssText = `
          position: fixed; inset: 0; background: #fff; pointer-events: none;
          z-index: 2000; opacity: 0; transition: opacity 1.1s ease;
        `;
        document.body.appendChild(overlay);
      }
      overlay.style.transition = 'none';
      overlay.style.opacity = String(THREE.MathUtils.clamp(exposure, 0.08, 0.98));
      requestAnimationFrame(() => {
        overlay!.style.transition = `opacity ${(0.45 + exposure * 1.8).toFixed(2)}s ease-out`;
        overlay!.style.opacity = '0';
      });
    }
  }

  private effectPosition(origin: Vec3): THREE.Vector3 {
    return new THREE.Vector3(origin.x * 0.01, origin.z * 0.01, -origin.y * 0.01);
  }

  private spawnRecordedEffect(effect: TempEffect): void {
    if (!this.scene) return;
    const pos = this.effectPosition(effect.origin);
    if (effect.kind === 3) {
      this.spawnDetonation(1, pos, effect.time);
      return;
    }
    if (effect.kind === 5) {
      this.spawnDetonation(3, pos, effect.time);
      return;
    }
    if ([0, 6, 7, 8, 18, 22, 24, 30, 31, 102, 113, 114, 126, 127].includes(effect.kind)) {
      const end = this.effectPosition(effect.end);
      if (end.distanceToSquared(pos) < 0.0001) return;
      const geometry = new THREE.BufferGeometry().setFromPoints([pos, end]);
      const material = new THREE.LineBasicMaterial({
        color: effect.color || 0xffd870,
        transparent: true,
        opacity: 0.85,
        depthWrite: false,
      });
      const line = new THREE.Line(geometry, material);
      this.scene.add(line);
      this.addEffect({ mesh: line, bornT: effect.time, ttl: 0.18, kind: 206 });
      return;
    }

    const isBlood = [101, 103, 115].includes(effect.kind);
    const isDecal = [13, 104, 109, 112, 116, 117, 118].includes(effect.kind);
    const color = isBlood ? 0x8f1515
      : effect.color ? effect.color
        : [2, 9, 111].includes(effect.kind) ? 0xffd58a
          : 0xffa040;
    const geometry = isDecal ? this.sharedFxGeometry.decal
      : isBlood ? this.sharedFxGeometry.blood
        : this.sharedFxGeometry.impact;
    const mesh = new THREE.Mesh(
      geometry,
      new THREE.MeshBasicMaterial({
        color,
        transparent: true,
        opacity: isDecal ? 0.72 : 0.9,
        depthWrite: !isDecal,
      }),
    );
    mesh.position.copy(pos);
    this.scene.add(mesh);
    this.addEffect({
      mesh,
      bornT: effect.time,
      ttl: isDecal ? 20 : isBlood ? 0.7 : 0.3,
      kind: isDecal ? 204 : 205,
    });
  }

  private addEffect(effect: { mesh: THREE.Object3D; bornT: number; ttl: number; kind: number }): void {
    this.fx.push(effect);
    while (this.fx.length > this.maxLiveEffects) {
      const oldest = this.fx.shift();
      if (oldest) this.disposeEffect(oldest.mesh);
    }
  }

  private disposeEffect(object: THREE.Object3D): void {
    this.scene?.remove(object);
    const shared = new Set<THREE.BufferGeometry>(Object.values(this.sharedFxGeometry));
    object.traverse((child) => {
      if (!(child instanceof THREE.Mesh)
          && !(child instanceof THREE.Line)
          && !(child instanceof THREE.Sprite)) return;
      if (!(child instanceof THREE.Sprite) && !shared.has(child.geometry)) child.geometry.dispose();
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      for (const material of materials) material.dispose();
    });
  }

  private clearRecordedFx(): void {
    for (const effect of this.fx) this.disposeEffect(effect.mesh);
    this.fx = [];
  }

  private updateRecordedEffects(): void {
    const effects = this.timeline?.temp_effects;
    if (!effects?.length) return;
    const time = this.currentTime;
    const discontinuity = this.lastTempEffectT < 0
      || time < this.lastTempEffectT
      || time - this.lastTempEffectT > 1;
    const from = discontinuity ? Math.max(0, time - 13) : this.lastTempEffectT;
    if (discontinuity) this.clearRecordedFx();

    let lo = 0;
    let hi = effects.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (effects[mid].time <= from) lo = mid + 1;
      else hi = mid;
    }
    for (let i = lo; i < effects.length && effects[i].time <= time; i++) {
      const effect = effects[i];
      const maxAge = effect.kind === 5 ? 13 : [13, 104, 109, 112, 116, 117, 118].includes(effect.kind) ? 20 : 1;
      if (time - effect.time <= maxAge) this.spawnRecordedEffect(effect);
    }
    this.lastTempEffectT = time;
  }

  /// Advance demo-time-driven effects (pause- and seek-safe)
  private updateFx(): void {
    if (!this.scene) return;
    this.fx = this.fx.filter((f) => {
      const age = this.currentTime - f.bornT;
      if (age < 0 || age > f.ttl) {
        this.disposeEffect(f.mesh);
        return false;
      }
      if (f.kind === 3) {
        // Billow: puffs drift outward/up, roil gently, fade in fast / out slow
        const expand = 1 - Math.exp(-age / 1.1);
        const fade = age > f.ttl - 3.5 ? (f.ttl - age) / 3.5 : 1;
        const fadeIn = Math.min(1, age / 0.35);
        (f.mesh as THREE.Group).rotation.y = age * 0.1;
        for (const child of f.mesh.children) {
          const puff = child as THREE.Sprite;
          const dir = puff.userData.dir as THREE.Vector3;
          const roil = Math.sin(age * 0.8 + puff.userData.phase) * 0.06;
          puff.position.copy(dir).multiplyScalar(0.3 + expand * 1.0 + roil);
          puff.scale.setScalar(puff.userData.size * (0.3 + expand * 0.95));
          (puff.material as THREE.SpriteMaterial).opacity =
            puff.userData.baseOpacity * fadeIn * fade;
        }
      } else if (f.kind === 206) {
        ((f.mesh as THREE.Line).material as THREE.LineBasicMaterial).opacity =
          0.85 * (1 - age / f.ttl);
      } else if (f.kind === 207) {
        const mesh = f.mesh as THREE.Mesh;
        const start = mesh.userData.start as THREE.Vector3;
        const velocity = mesh.userData.velocity as THREE.Vector3;
        mesh.position.copy(start).addScaledVector(velocity, age);
        mesh.position.y -= 2.4 * age * age;
        mesh.rotation.x = age * 18;
        mesh.rotation.z = age * 11;
      } else if (f.kind === 204) {
        const material = (f.mesh as THREE.Mesh).material as THREE.MeshBasicMaterial;
        material.opacity = age > f.ttl - 3 ? 0.72 * (f.ttl - age) / 3 : 0.72;
      } else {
        const mesh = f.mesh as THREE.Mesh;
        mesh.scale.setScalar(0.4 + age * 2.2);
        (mesh.material as THREE.MeshBasicMaterial).opacity = 0.9 * (1 - age / f.ttl);
      }
      return true;
    });
  }

  /// Blinking C4 indicator in the match bar while the bomb is down
  private updateBombIndicator(): void {
    let el = document.getElementById('bomb-indicator');
    const active = this.bombPlantedAt !== null && this.currentTime >= this.bombPlantedAt;
    if (!active) {
      el?.remove();
      return;
    }
    if (!el) {
      el = document.createElement('span');
      el.id = 'bomb-indicator';
      el.textContent = '🔻 C4';
      el.style.cssText = `
        color: #ff5252; font-size: 11px; font-weight: 700;
        animation: bomb-blink 1s step-end infinite;
      `;
      document.getElementById('round-timer')?.appendChild(el);
    }
  }

  private static readonly WEAPON_SOUNDS: Record<string, string> = {
    p_ak47: 'ak47-1', p_m4a1: 'm4a1-1', p_awp: 'awp1', p_deagle: 'deagle-1', p_mp5: 'mp5-1',
    p_usp: 'usp1', p_glock18: 'glock18-2', p_famas: 'famas-1', p_galil: 'galil-1',
    p_sg552: 'sg552-1', p_aug: 'aug-1', p_scout: 'scout_fire-1', p_p90: 'p90-1',
    p_mac10: 'mac10-1', p_tmp: 'tmp-1', p_ump45: 'ump45-1', p_m249: 'm249-1',
    p_p228: 'p228-1', p_elite: 'elite_fire', p_fiveseven: 'fiveseven', p_m3: 'm3-1',
    p_xm1014: 'xm1014-1', p_g3sg1: 'g3sg1-1', p_sg550: 'sg550-1', p_knife: 'knife_slash1',
  };

  private hasUsableNetworkGunshotAt(time: number, slot: number): boolean {
    const sounds = this.timeline?.network_sounds;
    if (!sounds?.length) return false;
    let left = 0;
    let right = sounds.length;
    while (left < right) {
      const middle = (left + right) >> 1;
      if (sounds[middle].time < time - 0.12) left = middle + 1;
      else right = middle;
    }
    const known = new Set(Object.values(DemoPlayer.WEAPON_SOUNDS));
    for (let index = left; index < sounds.length && sounds[index].time <= time + 0.12; index++) {
      const sound = sounds[index];
      const sample = sound.sample.replace(/^sound\//i, '').toLowerCase();
      const basename = sample.split('/').pop()?.replace(/\.wav$/i, '') ?? '';
      const shooterMatches = sound.entity === 0 || sound.entity === slot + 1;
      if (shooterMatches && sample.includes('weapons/') && known.has(basename)) return true;
    }
    return false;
  }

  private ensureAudio(): AudioContext | null {
    if (!this.audioCtx) {
      try {
        this.audioCtx = new AudioContext();
        this.audioCompressor = this.audioCtx.createDynamicsCompressor();
        this.audioCompressor.threshold.value = -15;
        this.audioCompressor.knee.value = 18;
        this.audioCompressor.ratio.value = 5;
        this.audioCompressor.attack.value = 0.004;
        this.audioCompressor.release.value = 0.16;
        this.audioMaster = this.audioCtx.createGain();
        this.audioMaster.gain.value = 0.86;
        this.audioCompressor.connect(this.audioMaster).connect(this.audioCtx.destination);
      } catch {
        return null;
      }
    }
    if (this.audioCtx.state === 'suspended') this.audioCtx.resume();
    return this.audioCtx;
  }

  private audioOutput(context: AudioContext): AudioNode {
    return this.audioCompressor ?? context.destination;
  }

  private toggleSound(): void {
    this.soundOn = !this.soundOn;
    if (!this.soundOn) this.stopActiveAudio();
    const button = document.getElementById('sound-btn');
    if (button) {
      button.textContent = this.soundOn ? '🔊' : '🔇';
      button.setAttribute('aria-label', this.soundOn ? 'Mute audio' : 'Unmute audio');
      button.title = `${this.soundOn ? 'Mute' : 'Unmute'} audio (M)`;
    }
    this.showAnnouncement(this.soundOn ? '🔊 Sound on' : '🔇 Sound off', '#dde5f0');
  }

  private updateAudioListener(): void {
    const context = this.audioCtx;
    const camera = this.camera;
    if (!context || !camera || !this.soundOn) return;
    const listener = context.listener;
    const forward = camera.getWorldDirection(new THREE.Vector3());
    listener.positionX.value = camera.position.x;
    listener.positionY.value = camera.position.y;
    listener.positionZ.value = camera.position.z;
    listener.forwardX.value = forward.x;
    listener.forwardY.value = forward.y;
    listener.forwardZ.value = forward.z;
    listener.upX.value = camera.up.x;
    listener.upY.value = camera.up.y;
    listener.upZ.value = camera.up.z;
  }

  private loadSound(name: string): Promise<AudioBuffer | null> {
    let cached = this.audioBuffers.get(name);
    if (!cached) {
      cached = (async () => {
        try {
          const ctx = this.ensureAudio();
          if (!ctx) return null;
          const resp = await fetch(`sounds/weapons/${name}.wav`);
          if (!resp.ok) return null;
          return await ctx.decodeAudioData(await resp.arrayBuffer());
        } catch {
          return null;
        }
      })();
      this.audioBuffers.set(name, cached);
    }
    return cached;
  }

  private loadRecordedSound(sample: string): Promise<AudioBuffer | null> {
    const safe = sample.replace(/^sound\//i, '').replace(/^\/+/, '');
    if (!safe || safe.includes('..') || !/^[a-z0-9_./-]+$/i.test(safe)) {
      return Promise.resolve(null);
    }
    const key = `recorded:${safe.toLowerCase()}`;
    let cached = this.audioBuffers.get(key);
    if (!cached) {
      cached = (async () => {
        try {
          const ctx = this.ensureAudio();
          if (!ctx) return null;
          const response = await fetch(`sounds/${safe}`);
          if (!response.ok) return null;
          return await ctx.decodeAudioData(await response.arrayBuffer());
        } catch {
          return null;
        }
      })();
      this.audioBuffers.set(key, cached);
    }
    return cached;
  }

  private startAudioSource(source: AudioBufferSourceNode, channel?: string): void {
    if (channel) {
      const previous = this.activeAudioChannels.get(channel);
      if (previous && previous !== source) {
        try {
          previous.stop();
        } catch {
          // The previous channel occupant may already have ended.
        }
        this.activeAudioSources.delete(previous);
      }
      this.activeAudioChannels.set(channel, source);
    }
    this.activeAudioSources.add(source);
    source.addEventListener('ended', () => {
      this.activeAudioSources.delete(source);
      if (channel && this.activeAudioChannels.get(channel) === source) {
        this.activeAudioChannels.delete(channel);
      }
    }, { once: true });
    source.start();
  }

  private stopActiveAudio(): void {
    for (const source of this.activeAudioSources) {
      try {
        source.stop();
      } catch {
        // Already ended.
      }
    }
    this.activeAudioSources.clear();
    this.activeAudioChannels.clear();
  }

  private updateRecordedSounds(): void {
    const demo = this.timeline;
    const time = this.currentTime;
    if (!this.soundOn || !demo?.sounds.length || demo.network_sounds.length
        || this.followTarget !== 'Spectator Camera') {
      this.lastDemoSoundT = time;
      return;
    }
    if (this.lastDemoSoundT < 0 || time < this.lastDemoSoundT || time - this.lastDemoSoundT > 1) {
      this.lastDemoSoundT = time;
      return;
    }
    let lo = 0;
    let hi = demo.sounds.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (demo.sounds[mid].time <= this.lastDemoSoundT) lo = mid;
      else hi = mid - 1;
    }
    if (demo.sounds[lo].time <= this.lastDemoSoundT) lo++;
    for (let i = lo; i < demo.sounds.length && demo.sounds[i].time <= time; i++) {
      const sound = demo.sounds[i];
      this.loadRecordedSound(sound.sample).then((buffer) => {
        const context = this.audioCtx;
        if (!buffer || !context || !this.soundOn || Math.abs(this.currentTime - sound.time) > 1.5) return;
        const source = context.createBufferSource();
        source.buffer = buffer;
        source.playbackRate.value = THREE.MathUtils.clamp(
          sound.pitch / 100 * this.playbackSpeed,
          0.25,
          4,
        );
        const gain = context.createGain();
        gain.gain.value = THREE.MathUtils.clamp(sound.volume, 0, 1) * 0.55;
        source.connect(gain).connect(this.audioOutput(context));
        this.startAudioSource(source);
      });
    }
    this.lastDemoSoundT = time;
  }

  private updateNetworkSounds(): void {
    const demo = this.timeline;
    const sounds = demo?.network_sounds;
    const time = this.currentTime;
    if (!this.soundOn || !sounds?.length) {
      this.lastNetworkSoundT = time;
      return;
    }
    if (this.lastNetworkSoundT < 0 || time < this.lastNetworkSoundT || time - this.lastNetworkSoundT > 1) {
      this.lastNetworkSoundT = time;
      return;
    }
    let lo = 0;
    let hi = sounds.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (sounds[mid].time <= this.lastNetworkSoundT) lo = mid + 1;
      else hi = mid;
    }
    for (let i = lo; i < sounds.length && sounds[i].time <= time; i++) {
      const sound = sounds[i];
      this.loadRecordedSound(sound.sample).then((buffer) => {
        const context = this.audioCtx;
        const camera = this.camera;
        if (!buffer || !context || !camera || !this.soundOn
            || Math.abs(this.currentTime - sound.time) > 1.5) return;
        const source = context.createBufferSource();
        source.buffer = buffer;
        source.playbackRate.value = THREE.MathUtils.clamp(
          sound.pitch / 100 * this.playbackSpeed,
          0.25,
          4,
        );
        const gain = context.createGain();
        gain.gain.value = THREE.MathUtils.clamp(sound.volume, 0, 1) * 0.68;
        const panner = context.createPanner();
        panner.panningModel = 'HRTF';
        panner.distanceModel = 'inverse';
        panner.refDistance = 1;
        panner.maxDistance = 80;
        panner.rolloffFactor = THREE.MathUtils.clamp(sound.attenuation, 0.1, 4);
        const position = this.effectPosition(sound.origin);
        panner.positionX.value = position.x;
        panner.positionY.value = position.y;
        panner.positionZ.value = position.z;

        source.connect(gain).connect(panner).connect(this.audioOutput(context));
        this.startAudioSource(source, `${sound.entity}:${sound.channel}`);
      });
    }
    this.lastNetworkSoundT = time;
  }

  /// Play a positional gunshot: volume falls off with distance to the camera
  private playShotSound(weaponModel: string, pos: THREE.Vector3): void {
    if (!this.soundOn || !this.camera) return;
    const file = DemoPlayer.WEAPON_SOUNDS[weaponModel];
    if (!file) return;
    const dist = this.camera.position.distanceTo(pos);
    const volume = Math.max(0, 1 - dist / 28) * 0.45;
    if (volume < 0.02) return;
    this.loadSound(file).then((buffer) => {
      const ctx = this.audioCtx;
      if (!buffer || !ctx) return;
      const src = ctx.createBufferSource();
      src.buffer = buffer;
      src.playbackRate.value = THREE.MathUtils.clamp(this.playbackSpeed, 0.25, 4);
      const gain = ctx.createGain();
      gain.gain.value = volume;
      // Simple stereo pan by camera-relative bearing
      const rel = pos.clone().sub(this.camera!.position);
      const camDir = new THREE.Vector3();
      this.camera!.getWorldDirection(camDir);
      const right = new THREE.Vector3().crossVectors(camDir, new THREE.Vector3(0, 1, 0));
      const pan = Math.max(-1, Math.min(1, rel.normalize().dot(right.normalize())));
      const panner = ctx.createStereoPanner();
      panner.pan.value = pan;
      src.connect(gain).connect(panner).connect(this.audioOutput(ctx));
      this.startAudioSource(src);
    });
  }

  private hasNetworkSoundNear(time: number, pattern: RegExp, entity?: number): boolean {
    const sounds = this.timeline?.network_sounds;
    if (!sounds?.length) return false;
    let left = 0;
    let right = sounds.length;
    while (left < right) {
      const middle = (left + right) >> 1;
      if (sounds[middle].time < time - .14) left = middle + 1;
      else right = middle;
    }
    for (let index = left; index < sounds.length; index++) {
      const sound = sounds[index];
      if (sound.time > time + 0.14) break;
      if (entity !== undefined && sound.entity !== 0 && sound.entity !== entity) continue;
      if (pattern.test(sound.sample)) return true;
    }
    return false;
  }

  private playFallbackSample(sample: string, volume: number, origin?: Vec3): void {
    if (!this.soundOn) return;
    this.loadRecordedSound(sample).then((buffer) => {
      const context = this.audioCtx;
      if (!buffer || !context || !this.soundOn) return;
      const source = context.createBufferSource();
      source.buffer = buffer;
      source.playbackRate.value = THREE.MathUtils.clamp(this.playbackSpeed, 0.25, 4);
      const gain = context.createGain();
      gain.gain.value = volume;
      source.connect(gain);
      if (origin) {
        const panner = context.createPanner();
        const position = this.effectPosition(origin);
        panner.panningModel = 'HRTF';
        panner.distanceModel = 'inverse';
        panner.refDistance = 1;
        panner.maxDistance = 65;
        panner.rolloffFactor = 1.15;
        panner.positionX.value = position.x;
        panner.positionY.value = position.y;
        panner.positionZ.value = position.z;
        gain.connect(panner).connect(this.audioOutput(context));
      } else {
        gain.connect(this.audioOutput(context));
      }
      this.startAudioSource(source);
    });
  }

  private updateFallbackAudio(states: PlayerState[], deaths: Map<string, number>): void {
    const demo = this.timeline;
    const time = this.currentTime;
    if (!demo || !this.soundOn) {
      this.lastFallbackAudioT = time;
      return;
    }
    if (this.lastFallbackAudioT < 0 || time < this.lastFallbackAudioT || time - this.lastFallbackAudioT > 1) {
      this.lastFallbackAudioT = time;
      this.nextFootstepAt.clear();
      return;
    }

    // Fill absent local footsteps from authoritative velocity. Existing demo
    // sounds always win, so this never doubles a recorded step.
    for (const state of states) {
      const speed = state.velocity ? Math.hypot(state.velocity.x, state.velocity.y) : 0;
      if (deaths.has(state.name) || speed < 105) {
        this.nextFootstepAt.delete(state.name);
        continue;
      }
      const next = this.nextFootstepAt.get(state.name) ?? time;
      if (time < next) continue;
      const player = this.players.find((candidate) => candidate.name === state.name);
      const entity = player ? player.index + 1 : undefined;
      if (!this.hasNetworkSoundNear(time, /player\/(pl_(step|tile|metal|dirt|grate|duct|snow)|foot)/i, entity)) {
        const variant = 1 + ((player?.index ?? 0) + Math.floor(time * 2)) % 4;
        this.playFallbackSample(`player/pl_step${variant}.wav`, 0.18, state.origin);
      }
      const cadence = THREE.MathUtils.lerp(0.46, 0.27, THREE.MathUtils.clamp((speed - 105) / 175, 0, 1));
      this.nextFootstepAt.set(state.name, time + cadence);
    }

    for (const event of demo.events) {
      if (event.time <= this.lastFallbackAudioT) continue;
      if (event.time > time) break;
      let sample: string | null = null;
      let pattern: RegExp | null = null;
      if (event.event_type === 'BombPlanted') { sample = 'weapons/c4_plant.wav'; pattern = /c4_plant|bombpl/i; }
      else if (event.event_type === 'BombDefused') { sample = 'weapons/c4_disarmed.wav'; pattern = /c4_disarm|bombdef/i; }
      else if (event.event_type === 'BombExploded') { sample = 'weapons/c4_explode1.wav'; pattern = /c4_explode|explode/i; }
      else if (event.event_type === 'RoundEnd' && /CT/i.test(event.data.winner ?? '')) {
        sample = 'radio/ctwin.wav'; pattern = /ctwin/i;
      } else if (event.event_type === 'RoundEnd' && /TERROR|^T$/i.test(event.data.winner ?? '')) {
        sample = 'radio/terwin.wav'; pattern = /terwin/i;
      }
      if (sample && pattern && !this.hasNetworkSoundNear(event.time, pattern)) {
        this.playFallbackSample(sample, 0.42);
      }
    }

    // Grenade bounce phases are inferred from vertical direction changes only
    // when the network stream supplied no bounce sound.
    let objectStart = 2;
    let objectEnd = demo.objTimes.length;
    while (objectStart < objectEnd) {
      const middle = (objectStart + objectEnd) >> 1;
      if (demo.objTimes[middle] <= this.lastFallbackAudioT) objectStart = middle + 1;
      else objectEnd = middle;
    }
    for (let index = Math.max(2, objectStart); index < demo.objTimes.length; index++) {
      const sampleTime = demo.objTimes[index];
      if (sampleTime > time) break;
      const entity = demo.objEnts[index];
      if (demo.objKinds[index] < 1 || demo.objKinds[index] > 3
          || demo.objEnts[index - 1] !== entity || demo.objEnts[index - 2] !== entity) continue;
      const before = demo.objPositions[(index - 1) * 3 + 2] - demo.objPositions[(index - 2) * 3 + 2];
      const after = demo.objPositions[index * 3 + 2] - demo.objPositions[(index - 1) * 3 + 2];
      if (before < -1.2 && after > 0.35 && !this.hasNetworkSoundNear(sampleTime, /bounce|grenade_hit/i, entity)) {
        this.playFallbackSample(`weapons/g_bounce${1 + entity % 5}.wav`, 0.2, {
          x: demo.objPositions[index * 3],
          y: demo.objPositions[index * 3 + 1],
          z: demo.objPositions[index * 3 + 2],
        });
      }
    }
    this.lastFallbackAudioT = time;
  }

  /// Fire muzzle flashes + sounds for shots that occurred since last frame
  private updateShots(): void {
    const d = this.timeline;
    if (!d?.shotTimes?.length) return;
    const t = this.currentTime;
    // Seeks: resync without retro-firing
    if (this.lastShotT < 0 || t < this.lastShotT || t - this.lastShotT > 1) {
      this.lastShotT = t;
      this.lastRenderedShotBySlot.clear();
      return;
    }
    const nSlots = d.slot_names.length;
    let lo = 0, hi = d.shotTimes.length - 1;
    while (lo < hi) { const m = (lo + hi + 1) >> 1; if (d.shotTimes[m] <= this.lastShotT) lo = m; else hi = m - 1; }
    if (d.shotTimes[lo] <= this.lastShotT) lo++;
    for (let i = lo; i < d.shotTimes.length && d.shotTimes[i] <= t; i++) {
      const slot = d.shotSlots[i];
      const shotTime = d.shotTimes[i];
      const previousShot = this.lastRenderedShotBySlot.get(slot);
      // Some HLTV streams repeat the same event script in adjacent network
      // messages. A 25 ms gap is below every CS 1.6 weapon's fire interval,
      // so these are duplicates rather than separate rounds.
      if (previousShot !== undefined && shotTime - previousShot < 0.025) continue;
      this.lastRenderedShotBySlot.set(slot, shotTime);
      const player = this.players.find((p) => p.index === slot);
      const mesh = player ? this.playerMeshes.get(player.name) : undefined;
      // First-person mode hides the followed player's world model. The shot
      // still needs audio (and viewmodel animation), so only reject hidden
      // meshes belonging to other players.
      const followedShooter = player?.name === this.followTarget;
      if (!mesh || (!mesh.visible && !followedShooter) || !this.scene) continue;
      const pivot = mesh.getObjectByName('yawPivot');
      const yaw = pivot?.rotation.y ?? 0;
      const muzzle = mesh.position.clone().add(new THREE.Vector3(
        Math.sin(yaw) * 0.5, 0.55, Math.cos(yaw) * 0.5
      ));
      const flash = new THREE.Mesh(
        this.sharedFxGeometry.muzzle,
        new THREE.MeshBasicMaterial({ color: 0xffd870, transparent: true, opacity: 0.95, depthWrite: false })
      );
      flash.position.copy(muzzle);
      this.scene.add(flash);
      this.addEffect({ mesh: flash, bornT: t, ttl: 0.07, kind: 98 });

      const shell = new THREE.Mesh(
        this.sharedFxGeometry.shell,
        new THREE.MeshBasicMaterial({ color: 0xb68a3d }),
      );
      shell.userData.start = muzzle.clone().add(new THREE.Vector3(0, -0.03, 0));
      shell.userData.velocity = new THREE.Vector3(
        Math.cos(yaw) * (0.65 + (slot % 3) * 0.08),
        0.8,
        -Math.sin(yaw) * (0.65 + (slot % 3) * 0.08),
      );
      shell.position.copy(shell.userData.start);
      this.scene.add(shell);
      this.addEffect({ mesh: shell, bornT: t, ttl: 0.8, kind: 207 });

      // Authoritative weapon at this moment for the sound
      const sIdx = player ? d.slot_names.indexOf(player.name) : -1;
      let weapon = 'p_ak47';
      if (sIdx >= 0) {
        let elo = 0, ehi = d.times.length - 1;
        while (elo < ehi) { const m = (elo + ehi + 1) >> 1; if (d.times[m] <= t) elo = m; else ehi = m - 1; }
        weapon = this.weaponModelName(d.weapons[elo * nSlots + sIdx]) ?? this.weaponForHeuristic(player!.name);
      }
      const recordedPovAudio = this.followTarget === 'Spectator Camera' && d.sounds.length > 0;
      const recordedNetworkShot = this.hasUsableNetworkGunshotAt(shotTime, slot);
      if (!recordedNetworkShot && !recordedPovAudio) {
        this.playShotSound(weapon, muzzle);
      }
    }
    this.lastShotT = t;
  }

  private clearDeathMarkers(): void {
    for (const marker of this.deathMarkers.values()) {
      this.scene!.remove(marker);
    }
    this.deathMarkers.clear();
  }

  private createAllPlayerMeshes(): void {
    // Clear existing player meshes
    for (const mesh of this.playerMeshes.values()) {
      this.scene!.remove(mesh);
    }
    this.playerMeshes.clear();
    this.clearDeathMarkers();
    for (const obj of this.objectMeshes.values()) this.scene!.remove(obj.group);
    this.objectMeshes.clear();
    for (const f of this.fx) this.disposeEffect(f.mesh);
    this.fx = [];

    // Don't pre-create meshes - they'll be created dynamically in updatePlayback()
    // when we have actual position data for them. This avoids having meshes
    // sitting at (0,0,0) for players we don't have position data for.
  }

  private onResize(): void {
    if (!this.camera || !this.renderer) return;
    this.camera.aspect = this.canvasContainer.clientWidth / this.canvasContainer.clientHeight;
    this.camera.updateProjectionMatrix();
    if (this.viewModelCamera) {
      this.viewModelCamera.aspect = this.camera.aspect;
      this.viewModelCamera.updateProjectionMatrix();
    }
    this.renderer.setSize(this.canvasContainer.clientWidth, this.canvasContainer.clientHeight);
  }

  private animate(): void {
    requestAnimationFrame(() => this.animate());
    const now = performance.now();
    const dt = Math.min(0.1, (now - this.lastAnimTime) / 1000);
    this.lastAnimTime = now;
    if (dt > 0) {
      this.frameTimeEma += (dt * 1000 - this.frameTimeEma) * 0.04;
      this.qualityFrameCounter++;
      if (this.renderQuality === 'auto' && this.qualityFrameCounter >= 45) {
        this.qualityFrameCounter = 0;
        const maxRatio = Math.min(window.devicePixelRatio, 2);
        const nextRatio = this.frameTimeEma > 38
          ? Math.max(0.67, this.renderScale - 0.5)
          : this.frameTimeEma > 22
            ? Math.max(0.67, this.renderScale - 0.25)
            : this.frameTimeEma < 15.5
              ? Math.min(maxRatio, this.renderScale + 0.125)
              : this.renderScale;
        if (Math.abs(nextRatio - this.renderScale) > 0.01) {
          this.renderScale = nextRatio;
          this.renderer?.setPixelRatio(nextRatio);
          this.renderer?.setSize(this.canvasContainer.clientWidth, this.canvasContainer.clientHeight);
        }
      }
    }
    // Advance replay state in the same callback that renders it. The previous
    // pair of independent rAF loops could render an old state and then spend
    // the remainder of the frame updating the next one, producing uneven
    // cadence even when both callbacks were individually fast.
    if (this.isPlaying) this.advancePlayback(now);
    if (this.flyMode) this.updateFlyCamera(dt);
    else if (!this.followTarget) this.controls?.update();
    this.animateViewModel();
    this.updateAudioListener();
    this.fadeTracers();
    if (this.scene && this.camera && this.renderer) {
      this.renderer.render(this.scene, this.camera);
      if (this.viewModelScene && this.viewModelCamera && this.viewModel?.visible) {
        // Match demo-provided FOV changes while keeping the viewmodel's depth
        // independent from the BSP and player geometry.
        if (this.viewModelCamera.fov !== this.camera.fov) {
          this.viewModelCamera.fov = this.camera.fov;
          this.viewModelCamera.updateProjectionMatrix();
        }
        this.renderer.autoClear = false;
        this.renderer.clearDepth();
        this.renderer.render(this.viewModelScene, this.viewModelCamera);
        this.renderer.autoClear = true;
      }
    }
  }

  /// Draw a brief line from killer to victim when a kill happens near "now"
  private spawnKillTracer(killerName: string, victimName: string): void {
    const killer = this.playerMeshes.get(killerName);
    const victim = this.playerMeshes.get(victimName);
    if (!killer || !victim || !this.scene) return;

    const HEAD = 1.5;
    const from = killer.position.clone().add(new THREE.Vector3(0, HEAD, 0));
    const to = victim.position.clone().add(new THREE.Vector3(0, HEAD * 0.6, 0));
    const geometry = new THREE.BufferGeometry().setFromPoints([from, to]);
    const material = new THREE.LineBasicMaterial({
      color: 0xffe0a0,
      transparent: true,
      opacity: 0.9,
    });
    const line = new THREE.Line(geometry, material);
    line.renderOrder = 998;
    this.scene.add(line);
    this.tracers.push({ line, expiresAt: performance.now() + 700 });
  }

  private fadeTracers(): void {
    if (!this.tracers.length || !this.scene) return;
    const now = performance.now();
    this.tracers = this.tracers.filter(({ line, expiresAt }) => {
      const remaining = expiresAt - now;
      if (remaining <= 0) {
        this.scene!.remove(line);
        line.geometry.dispose();
        (line.material as THREE.Material).dispose();
        return false;
      }
      (line.material as THREE.LineBasicMaterial).opacity = 0.9 * (remaining / 700);
      return true;
    });
  }

  private setupEventListeners(): void {
    // Drag and drop
    this.dropZone.addEventListener('dragover', (e) => {
      e.preventDefault();
      this.dropZone.classList.add('dragover');
    });

    this.dropZone.addEventListener('dragleave', () => {
      this.dropZone.classList.remove('dragover');
    });

    this.dropZone.addEventListener('drop', (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.dropZone.classList.remove('dragover');
      if (e.dataTransfer?.files) {
        this.handleFiles(e.dataTransfer.files);
      }
    });

    const openFilePicker = () => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.dem,.bsp';
      input.multiple = true;
      input.onchange = () => input.files && this.handleFiles(input.files);
      input.click();
    };
    this.dropZone.addEventListener('click', openFilePicker);
    this.dropZone.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        openFilePicker();
      }
    });

    // Global drag and drop
    document.body.addEventListener('dragover', (e) => e.preventDefault());
    document.body.addEventListener('drop', (e) => {
      e.preventDefault();
      if (e.dataTransfer?.files) this.handleFiles(e.dataTransfer.files);
    });

    document.getElementById('demo-search')?.addEventListener('input', (e) => {
      this.demoSearch = (e.target as HTMLInputElement).value.trim().toLowerCase();
      this.renderDemoLibrary();
    });
    document.getElementById('demo-filters')?.addEventListener('click', (e) => {
      const button = (e.target as HTMLElement).closest<HTMLButtonElement>('.demo-filter');
      if (!button?.dataset.map) return;
      this.demoMapFilter = button.dataset.map;
      this.renderDemoLibrary();
    });
    document.getElementById('demo-list')?.addEventListener('click', (e) => {
      const card = (e.target as HTMLElement).closest<HTMLButtonElement>('.demo-card');
      if (!card?.dataset.index) return;
      const item = this.demoLibrary[Number(card.dataset.index)];
      if (item) void this.loadLibraryDemo(item);
    });

    // Browsers require a user gesture before audio can start
    document.addEventListener('click', () => this.ensureAudio(), { once: true });
    document.addEventListener('keydown', () => this.ensureAudio(), { once: true });

    // Playback
    this.playBtn.addEventListener('click', () => this.togglePlayback());
    this.timelineEl.addEventListener('click', (e) => {
      const rect = this.timelineEl.getBoundingClientRect();
      this.seekTo((e.clientX - rect.left) / rect.width);
    });
    this.timelineEl.addEventListener('mousemove', (event) => {
      if (!this.timeline || !this.duration) return;
      const rect = this.timelineEl.getBoundingClientRect();
      const percent = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
      const time = percent * this.duration;
      let preview = document.getElementById('timeline-preview');
      if (!preview) {
        preview = document.createElement('div');
        preview.id = 'timeline-preview';
        this.timelineEl.appendChild(preview);
      }
      const nearby = this.timeline.events.find(
        (item) => Math.abs(item.time - time) < 2.5
          && ['Kill', 'BombPlanted', 'BombDefused', 'BombExploded'].includes(item.event_type),
      );
      const detail = nearby?.event_type === 'Kill'
        ? `${nearby.data.killer ?? '?'} → ${nearby.data.victim ?? '?'}`
        : nearby?.event_type.replace(/([a-z])([A-Z])/g, '$1 $2') ?? `Round ${this.roundIndexAt(time) + 1}`;
      preview.innerHTML = `<strong>${this.formatTime(time)}</strong><span>${this.escapeHtml(detail)}</span>`;
      preview.style.left = `${percent * 100}%`;
      preview.classList.add('visible');
    });
    this.timelineEl.addEventListener('mouseleave', () => {
      document.getElementById('timeline-preview')?.classList.remove('visible');
    });
    this.speedSelect.addEventListener('change', () => {
      this.playbackSpeed = parseFloat(this.speedSelect.value);
    });
    document.getElementById('playback-mode-select')?.addEventListener('change', (event) => {
      this.setPlaybackMode((event.target as HTMLSelectElement).value as PlaybackMode);
    });
    document.getElementById('quality-select')?.addEventListener('change', (event) => {
      this.setRenderQuality((event.target as HTMLSelectElement).value as RenderQuality);
    });
    document.getElementById('hud-mode-select')?.addEventListener('change', (event) => {
      this.setHudMode((event.target as HTMLSelectElement).value as HudMode);
    });
    document.getElementById('help-btn')?.addEventListener('click', () => {
      document.getElementById('help-overlay')?.classList.toggle('hidden');
    });
    document.getElementById('diagnostics-btn')?.addEventListener('click', () => {
      this.toggleDiagnostics();
    });
    document.getElementById('diagnostics-close')?.addEventListener('click', () => {
      this.setDiagnosticsVisible(false);
    });
    document.getElementById('diagnostics-rerun')?.addEventListener('click', () => {
      this.runReplayVerification();
    });
    document.getElementById('sound-btn')?.addEventListener('click', () => this.toggleSound());
    document.getElementById('highlights-btn')?.addEventListener('click', () => this.toggleEventNavigator());
    document.getElementById('studio-btn')?.addEventListener('click', () => this.toggleStudio());
    document.getElementById('studio-close')?.addEventListener('click', () => this.toggleStudio(false));
    document.getElementById('director-btn')?.addEventListener('click', () => this.toggleDirector());
    document.getElementById('kill-replay-btn')?.addEventListener('click', () => this.startKillReplay());
    document.getElementById('tactical-btn')?.addEventListener('click', () => this.toggleTacticalMap());
    document.getElementById('economy-btn')?.addEventListener('click', () => this.toggleEconomy());
    document.getElementById('bookmark-btn')?.addEventListener('click', () => this.addBookmark());
    document.getElementById('share-btn')?.addEventListener('click', () => { void this.copyShareLink(); });
    document.getElementById('screenshot-btn')?.addEventListener('click', () => this.captureScreenshot());
    document.getElementById('clip-btn')?.addEventListener('click', () => this.recordClip());
    document.getElementById('bookmark-list')?.addEventListener('click', (event) => {
      const row = (event.target as HTMLElement).closest<HTMLElement>('.bookmark-row');
      if (!row?.dataset.id) return;
      const bookmark = this.bookmarks.find((item) => item.id === row.dataset.id);
      if (!bookmark) return;
      if ((event.target as HTMLElement).closest('button')) {
        this.bookmarks = this.bookmarks.filter((item) => item.id !== bookmark.id);
        localStorage.setItem(this.bookmarkStorageKey(), JSON.stringify(this.bookmarks));
        this.renderBookmarks();
        return;
      }
      this.seekToTime(bookmark.time);
      if (bookmark.follow) this.setFollowTarget(bookmark.follow);
    });
    document.getElementById('event-nav-close')?.addEventListener('click', () => this.toggleEventNavigator(false));
    document.querySelector('.event-nav-tabs')?.addEventListener('click', (event) => {
      const button = (event.target as HTMLElement).closest<HTMLButtonElement>('button[data-view]');
      if (button?.dataset.view) this.renderEventNavigator(button.dataset.view);
    });
    document.getElementById('event-nav-list')?.addEventListener('click', (event) => {
      const button = (event.target as HTMLElement).closest<HTMLButtonElement>('.nav-event');
      const time = Number(button?.dataset.time);
      if (!button || !Number.isFinite(time) || !this.duration) return;
      this.seekTo(time / this.duration);
      if (button.dataset.follow) this.setFollowTarget(button.dataset.follow);
    });
    document.getElementById('replay-btn')?.addEventListener('click', () => {
      const seconds = Number((document.getElementById('skip-select') as HTMLSelectElement | null)?.value) || 5;
      this.replayPrevious(seconds);
    });
    document.getElementById('prev-player-btn')?.addEventListener('click', () => this.cycleFollowTarget(-1));
    document.getElementById('next-player-btn')?.addEventListener('click', () => this.cycleFollowTarget(1));
    document.getElementById('camera-back-btn')?.addEventListener('click', () => this.restorePreviousCamera());
    document.getElementById('spectator-roster')?.addEventListener('click', (event) => {
      const button = (event.target as HTMLElement).closest<HTMLButtonElement>('[data-player]');
      if (button?.dataset.player && !button.disabled) this.setFollowTarget(button.dataset.player);
    });
    document.getElementById('prev-round-btn')?.addEventListener('click', () => {
      this.seekToRound(this.roundIndexAt(this.currentTime) - 1);
    });
    document.getElementById('next-round-btn')?.addEventListener('click', () => {
      this.seekToRound(this.roundIndexAt(this.currentTime) + 1);
    });

    // Fly-mode movement keys + mouse look
    document.addEventListener('keyup', (e) => this.flyKeys.delete(e.code));
    document.addEventListener('mousemove', (e) => {
      if (this.flyMode && document.pointerLockElement === this.renderer?.domElement) {
        this.flyYaw -= e.movementX * 0.0022;
        this.flyPitch = Math.max(-1.55, Math.min(1.55, this.flyPitch - e.movementY * 0.0022));
      }
    });
    this.canvasContainer.addEventListener('click', () => {
      if (this.flyMode && !document.pointerLockElement) {
        this.renderer?.domElement.requestPointerLock();
      }
    });

    // Keyboard
    document.addEventListener('keydown', (e) => {
      if ((e.target as HTMLElement).matches('input, textarea, select')) return;
      if (this.flyMode) {
        this.flyKeys.add(e.code);
        if (e.code === 'Escape' || e.code === 'KeyF') { this.exitFlyMode(); return; }
        if (e.code !== 'Space') return; // movement keys consumed; Space still plays
      }
      if (e.code === 'KeyF') { this.toggleFlyMode(); return; }
      if (e.code === 'Space') { e.preventDefault(); this.togglePlayback(); }
      const skip = Number((document.getElementById('skip-select') as HTMLSelectElement | null)?.value) || 5;
      if (e.code === 'ArrowLeft') this.seekRelative(-skip);
      if (e.code === 'ArrowRight') this.seekRelative(skip);
      if (e.code === 'PageUp') { e.preventDefault(); this.cycleFollowTarget(-1); }
      if (e.code === 'PageDown') { e.preventDefault(); this.cycleFollowTarget(1); }
      if (e.code === 'Backspace') { e.preventDefault(); this.restorePreviousCamera(); }
      if (e.code === 'KeyX') this.toggleSlowMotion();
      if (e.code === 'Escape') {
        const help = document.getElementById('help-overlay');
        const navigator = document.getElementById('event-navigator');
        if (help && !help.classList.contains('hidden')) help.classList.add('hidden');
        else if (navigator && !navigator.classList.contains('hidden')) navigator.classList.add('hidden');
        else this.setFollowTarget(null);
      }
      if (e.code === 'BracketLeft') this.seekToRound(this.roundIndexAt(this.currentTime) - 1);
      if (e.code === 'BracketRight') this.seekToRound(this.roundIndexAt(this.currentTime) + 1);
      // Frame-step by one sample (50ms) — most useful while paused
      if (e.code === 'Comma') this.seekRelative(-0.05);
      if (e.code === 'Period') this.seekRelative(0.05);
      if (e.code === 'Tab') { e.preventDefault(); this.toggleStats(); }
      if (e.code === 'KeyD') this.toggleDiagnostics();
      if (e.code === 'KeyH') this.cycleHudMode();
      if (e.key === '?') document.getElementById('help-overlay')?.classList.toggle('hidden');
      if (e.code === 'KeyK') this.killCam();
      if (e.code === 'KeyS') this.toggleStudio();
      if (e.code === 'KeyT') this.toggleTacticalMap();
      if (e.code === 'KeyB') this.addBookmark();
      if (e.code === 'KeyM') {
        this.toggleSound();
      }
      // 1-9 select players in list order
      if (e.code.startsWith('Digit')) {
        const n = parseInt(e.code.slice(5), 10);
        if (n >= 1 && n <= 9) {
          const sorted = [...this.players].sort((a, b) => a.index - b.index);
          const player = sorted[n - 1];
          if (player) this.setFollowTarget(player.name);
        }
      }
    });

    // Load map button
    document.getElementById('load-map-btn')?.addEventListener('click', () => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.bsp';
      input.onchange = () => input.files?.[0] && this.loadBSP(input.files[0]);
      input.click();
    });
  }

  private async loadDemoLibrary(): Promise<void> {
    const list = document.getElementById('demo-list');
    try {
      const response = await fetch('/api/demos');
      if (!response.ok) throw new Error(`Demo library returned ${response.status}`);
      this.demoLibrary = await response.json() as DemoLibraryItem[];
      this.renderDemoLibrary();
    } catch (error) {
      console.warn('Local demo library unavailable:', error);
      if (list) {
        list.innerHTML = `
          <div class="demo-empty">
            Local archive unavailable.<br>Drop a .dem file here to get started.
          </div>`;
      }
      const count = document.getElementById('demo-count');
      if (count) count.textContent = 'Local files';
    }
  }

  private renderDemoLibrary(): void {
    const list = document.getElementById('demo-list');
    const filters = document.getElementById('demo-filters');
    if (!list || !filters) return;

    const maps = [...new Set(this.demoLibrary.map((item) => item.map))]
      .filter((map) => map && map !== 'unknown')
      .sort();
    filters.innerHTML = ['all', ...maps].map((map) => `
      <button class="demo-filter${this.demoMapFilter === map ? ' active' : ''}"
        type="button" data-map="${this.escapeHtml(map)}">
        ${map === 'all' ? 'All maps' : this.escapeHtml(this.mapDisplayName(map))}
      </button>
    `).join('');

    const visible = this.demoLibrary.filter((item) => {
      const matchesMap = this.demoMapFilter === 'all' || item.map === this.demoMapFilter;
      const haystack = `${item.name} ${item.path} ${item.map}`.toLowerCase();
      return matchesMap && (!this.demoSearch || haystack.includes(this.demoSearch));
    });

    const count = document.getElementById('demo-count');
    if (count) count.textContent = `${visible.length} recording${visible.length === 1 ? '' : 's'}`;
    const landingDemoCount = document.getElementById('landing-demo-count');
    if (landingDemoCount) landingDemoCount.textContent = this.demoLibrary.length.toString();
    const landingMapCount = document.getElementById('landing-map-count');
    if (landingMapCount) landingMapCount.textContent = maps.length.toString();

    if (visible.length === 0) {
      list.innerHTML = '<div class="demo-empty">No recordings match this filter.</div>';
      return;
    }

    list.innerHTML = visible.map((item) => {
      const index = this.demoLibrary.indexOf(item);
      const featured = !item.path.startsWith('corpus/');
      return `
        <button class="demo-card" type="button" data-index="${index}"
          title="Play ${this.escapeHtml(item.name)}">
          <span class="demo-card-icon">${featured ? '★' : '▶'}</span>
          <span class="demo-card-copy">
            <span class="demo-card-title">${this.escapeHtml(this.friendlyDemoName(item.name))}</span>
            <span class="demo-card-meta">
              <span class="map-badge">${this.escapeHtml(this.mapDisplayName(item.map))}</span>
              <span>${this.formatBytes(item.size)}</span>
              <span>${featured ? 'Featured' : 'Match archive'}</span>
            </span>
          </span>
          <span class="demo-card-play">→</span>
        </button>
      `;
    }).join('');
    if (!this.sharedAutoLoadStarted && location.hash) {
      const sharedDemo = new URLSearchParams(location.hash.slice(1)).get('demo');
      const match = sharedDemo
        ? this.demoLibrary.find((item) => item.name === sharedDemo || item.path === sharedDemo)
        : null;
      if (match) {
        this.sharedAutoLoadStarted = true;
        void this.loadLibraryDemo(match);
      }
    }
  }

  private friendlyDemoName(filename: string): string {
    return filename
      .replace(/\.dem$/i, '')
      .replace(/_/g, ' ')
      .replace(/\s*vs\s*/gi, ' vs ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private mapDisplayName(map: string): string {
    const names: Record<string, string> = {
      de_dust2: 'Dust II',
      de_inferno: 'Inferno',
      de_nuke: 'Nuke',
      de_train: 'Train',
      de_cbble: 'Cobblestone',
      de_cpl_mill: 'CPL Mill',
      de_cpl_strike: 'CPL Strike',
      de_prodigy: 'Prodigy',
    };
    return names[map.toLowerCase()] ?? map.replace(/^de_/, '').replace(/_/g, ' ');
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(bytes >= 10 * 1024 * 1024 ? 0 : 1)} MB`;
  }

  private async loadLibraryDemo(item: DemoLibraryItem): Promise<void> {
    const library = document.querySelector<HTMLElement>('.demo-library');
    const progressEl = document.getElementById('load-progress')!;
    const fillEl = document.getElementById('load-progress-fill')!;
    const labelEl = document.getElementById('load-progress-label')!;
    library?.classList.add('loading');
    progressEl.classList.remove('hidden');
    fillEl.style.width = '8%';
    labelEl.textContent = `Loading ${this.friendlyDemoName(item.name)} · ${this.formatBytes(item.size)}…`;
    try {
      const cache = 'caches' in window ? await caches.open('cs16-demo-files-v1') : null;
      let response = await cache?.match(item.url);
      if (!response) {
        response = await fetch(item.url);
        if (response.ok) void cache?.put(item.url, response.clone());
      }
      if (!response.ok) throw new Error(`Unable to load demo (${response.status})`);
      const data = await response.arrayBuffer();
      fillEl.style.width = '18%';
      await this.loadDemo(new File([data], item.name, {
        type: 'application/octet-stream',
        lastModified: 0,
      }));
    } catch (error) {
      console.error('Failed to load library demo:', error);
      fillEl.style.width = '100%';
      labelEl.textContent = 'Could not load this recording.';
      window.setTimeout(() => progressEl.classList.add('hidden'), 2200);
    } finally {
      library?.classList.remove('loading');
    }
  }

  private handleFiles(files: FileList): void {
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const ext = file.name.toLowerCase().split('.').pop();
      if (ext === 'dem') this.loadDemo(file);
      else if (ext === 'bsp') this.loadBSP(file);
    }
  }

  private async loadDemo(file: File): Promise<void> {
    const progressEl = document.getElementById('load-progress')!;
    const fillEl = document.getElementById('load-progress-fill')!;
    const labelEl = document.getElementById('load-progress-label')!;
    try {
      progressEl.classList.remove('hidden');
      fillEl.style.width = '0%';
      labelEl.textContent = 'Reading file…';

      const cacheKey = `${file.name}:${file.size}:${file.lastModified}`;
      this.demoIdentity = file.name;
      this.sharedLocationApplied = false;
      let result = this.parsedDemoCache.get(cacheKey);
      if (result) {
        fillEl.style.width = '100%';
        labelEl.textContent = 'Restoring cached timeline…';
      } else {
        const data = await file.arrayBuffer();
        result = await parseDemoWithProgress(data, (fraction) => {
          const pct = Math.round(fraction * 100);
          fillEl.style.width = `${pct}%`;
          labelEl.textContent = fraction < 0.9 ? `Parsing demo… ${pct}%` : `Building timeline… ${pct}%`;
        });
        this.parsedDemoCache.set(cacheKey, result);
        // Retain the current and previous recording without allowing large
        // tournament demos to grow memory without bound.
        while (this.parsedDemoCache.size > 2) {
          const oldest = this.parsedDemoCache.keys().next().value as string | undefined;
          if (oldest === undefined) break;
          this.parsedDemoCache.delete(oldest);
        }
      }

      this.timeline = result;
      this.duration = result.duration;
      this.mapName = result.map_name;
      this.players = result.players || [];
      this.assetPreflight = null;
      this.preloadScheduled = false;
      this.lastPreloadTime = -Infinity;
      this.deathsCacheTimeline = null;
      this.deathsCacheTime = Number.NaN;
      this.deathsCache.clear();
      this.buildHudTracks();
      this.loadBookmarks();
      this.runReplayVerification();

      // Update UI
      this.dropOverlay.classList.add('hidden');
      this.controlsEl.classList.remove('hidden');
      this.infoPanel.classList.remove('hidden');

      this.mapNameEl.textContent = this.mapName;
      this.durationEl.textContent = this.formatTime(this.duration);
      this.playerCountEl.textContent = this.players.length.toString();

      // Round navigation + time-varying team data
      this.buildRoundsAndModels();
      this.renderTimelineMarkers();
      this.renderEventNavigator('rounds');
      this.updateRoundIndicator();
      this.lastSeen.clear();

      // Show player list
      this.renderPlayerList();

      // Create player meshes for all players
      this.createAllPlayerMeshes();

      // Reset camera follow from any previous demo
      this.cameraHistory = [];
      this.preferredFollowTeam = null;
      this.setFollowTarget(null);

      // Create event feed
      this.createEventFeed();

      // Reset and show scoreboard
      this.resetScoreboard();
      this.resetRoundTimer();

      // Reset playback
      this.currentTime = 0;
      this.isPlaying = false;
      this.updateUI();
      this.updatePlayback();
      this.applySharedLocation();
      void this.preloadNearTime(0);

      // Hide single recorder mesh if we have multiple players
      if (this.playerMesh) {
        this.playerMesh.visible = this.players.length === 0;
      }

      // Try auto-load map
      void this.tryAutoLoadMap(this.mapName).finally(() => this.runAssetPreflight());

    } catch (error) {
      console.error('Failed to load demo:', error);
      alert('Failed to load demo file.');
    } finally {
      progressEl.classList.add('hidden');
    }
  }

  private async loadBSP(file: File): Promise<void> {
    try {
      const data = await file.arrayBuffer();
      await this.loadBSPData(data, file.name.replace('.bsp', ''));
    } catch (error) {
      console.error('Failed to load BSP:', error);
      alert('Failed to load BSP file.');
    }
  }

  /// Fetch the WAD files a map may need (best effort; missing ones are fine).
  /// Nuke, Train, and Prodigy keep nearly all of their pixels in external archives.
  private async fetchWads(mapName: string): Promise<ArrayBuffer[]> {
    const defaultWads = ['cstrike.wad', 'cs_dust.wad', 'cs_cbble.wad', 'decals.wad'];
    const mapWads: Record<string, string[]> = {
      de_nuke: ['classic_maps.wad'],
      de_train: ['classic_maps.wad'],
      de_prodigy: ['prodigy_map.wad'],
    };
    const names = mapWads[mapName.toLowerCase()] ?? defaultWads;
    const results = await Promise.all(names.map((name) => {
      let cached = this.wadFileCache.get(name);
      if (!cached) {
        cached = (async () => {
          try {
            const resp = await fetch(`wads/${name}`);
            if (!resp.ok) {
              this.reportMissingAsset(`wads/${name}`);
              return null;
            }
            const buf = await resp.arrayBuffer();
            // Vite dev server returns index.html for missing files; check magic.
            if (buf.byteLength < 4 || new DataView(buf).getUint32(0, true) !== 0x33444157) {
              this.reportMissingAsset(`wads/${name}`);
              return null;
            }
            return buf; // "WAD3"
          } catch {
            this.reportMissingAsset(`wads/${name}`);
            return null;
          }
        })();
        this.wadFileCache.set(name, cached);
      }
      return cached;
    }));
    return results.filter((b): b is ArrayBuffer => b !== null);
  }

  private async loadBSPData(data: ArrayBuffer, name: string): Promise<void> {
    const wads = await this.fetchWads(name);
    const bsp = await parseBspTextured(data, wads);

    // Remove old map
    if (this.mapMesh) {
      this.scene!.remove(this.mapMesh);
    }
    this.dynamicBrushes = [];
    this.animatedMapMaterials = [];

    // Hide grid
    const grid = this.scene!.getObjectByName('grid');
    if (grid) grid.visible = false;

    const attributes = {
      position: new THREE.BufferAttribute(bsp.positions, 3),
      normal: new THREE.BufferAttribute(bsp.normals, 3),
      color: new THREE.BufferAttribute(bsp.colors, 3),
      uv: new THREE.BufferAttribute(bsp.uvs, 2),
    };
    const createGeometry = () => {
      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute('position', attributes.position);
      geometry.setAttribute('normal', attributes.normal);
      geometry.setAttribute('color', attributes.color);
      geometry.setAttribute('uv', attributes.uv);
      return geometry;
    };

    // One material per texture group. Vertex colors carry the baked lightmap,
    // which Three multiplies against the texture map.
    const materialCache = new Map<string, THREE.MeshBasicMaterial>();
    const materials: THREE.Material[] = bsp.groups.map((g) => {
      const materialKey = g.pix_offset >= 0
        ? `${g.pix_offset}:${g.width}:${g.height}:${g.name.startsWith('{')}`
        : `flat:${g.name.startsWith('{')}`;
      const existing = materialCache.get(materialKey);
      if (existing) return existing;
      if (g.pix_offset >= 0 && g.width > 0) {
        const pixels = bsp.pixels.subarray(g.pix_offset, g.pix_offset + g.width * g.height * 4);
        const tex = new THREE.DataTexture(pixels, g.width, g.height, THREE.RGBAFormat);
        tex.wrapS = THREE.RepeatWrapping;
        tex.wrapT = THREE.RepeatWrapping;
        tex.magFilter = THREE.LinearFilter;
        tex.minFilter = THREE.LinearMipmapLinearFilter;
        tex.generateMipmaps = true;
        tex.colorSpace = THREE.SRGBColorSpace;
        tex.needsUpdate = true;
        const material = new THREE.MeshBasicMaterial({
          map: tex,
          vertexColors: true,
          side: THREE.DoubleSide,
          transparent: g.name.startsWith('{'),
          alphaTest: g.name.startsWith('{') ? 0.5 : 0,
        });
        if (/water|!|slime|lava/i.test(g.name)) {
          material.transparent = true;
          material.opacity = 0.76;
          material.depthWrite = false;
          this.animatedMapMaterials.push(material);
        }
        materialCache.set(materialKey, material);
        return material;
      }
      const material = new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.DoubleSide });
      materialCache.set(materialKey, material);
      return material;
    });
    const root = new THREE.Group();
    root.name = 'bspMap';
    const worldGeometry = createGeometry();
    const entitiesByModel = new Map<number, BspEntity>();
    const prop = (entity: BspEntity, key: string) => entity.properties.find(([name]) => name === key)?.[1];
    for (const entity of bsp.entities) {
      const model = prop(entity, 'model');
      if (model?.startsWith('*')) entitiesByModel.set(Number(model.slice(1)), entity);
    }
    const groupsByModel = new Map<number, Array<{ group: typeof bsp.groups[number]; material: number }>>();
    bsp.groups.forEach((group, material) => {
      const entries = groupsByModel.get(group.model_index) ?? [];
      entries.push({ group, material });
      groupsByModel.set(group.model_index, entries);
    });
    for (const entry of groupsByModel.get(0) ?? []) {
      worldGeometry.addGroup(entry.group.vert_start, entry.group.vert_count, entry.material);
    }
    const world = new THREE.Mesh(worldGeometry, materials);
    world.name = 'worldspawn';
    root.add(world);

    const corners = new Map<string, BspEntity>();
    for (const entity of bsp.entities) {
      const targetname = prop(entity, 'targetname');
      if (entity.classname === 'path_corner' && targetname) corners.set(targetname, entity);
    }
    for (const [modelIndex, entries] of groupsByModel) {
      if (modelIndex === 0) continue;
      const geometry = createGeometry();
      for (const entry of entries) geometry.addGroup(entry.group.vert_start, entry.group.vert_count, entry.material);
      geometry.computeBoundingBox();
      const box = geometry.boundingBox ?? new THREE.Box3();
      // computeBoundingBox sees every shared vertex, so derive this submodel's
      // bounds from its own draw ranges instead.
      box.makeEmpty();
      for (const entry of entries) {
        const end = entry.group.vert_start + entry.group.vert_count;
        for (let vertex = entry.group.vert_start; vertex < end; vertex++) {
          box.expandByPoint(new THREE.Vector3(
            bsp.positions[vertex * 3], bsp.positions[vertex * 3 + 1], bsp.positions[vertex * 3 + 2],
          ));
        }
      }
      const entity = entitiesByModel.get(modelIndex);
      const mesh = new THREE.Mesh(geometry, materials);
      if (!entity) {
        root.add(mesh);
        continue;
      }
      const center = box.getCenter(new THREE.Vector3());
      const extent = box.getSize(new THREE.Vector3());
      const origin = entity.origin
        ? new THREE.Vector3(entity.origin.x * .01, entity.origin.z * .01, -entity.origin.y * .01)
        : center;
      const pivot = new THREE.Group();
      pivot.name = `${entity.classname}:${modelIndex}`;
      pivot.position.copy(origin);
      mesh.position.copy(origin).multiplyScalar(-1);
      pivot.add(mesh);
      root.add(pivot);
      const path: THREE.Vector3[] = [];
      let target = prop(entity, 'target');
      const visited = new Set<string>();
      while (target && !visited.has(target) && path.length < 64) {
        visited.add(target);
        const corner = corners.get(target);
        if (!corner?.origin) break;
        path.push(new THREE.Vector3(corner.origin.x * .01, corner.origin.z * .01, -corner.origin.y * .01));
        target = prop(corner, 'target');
      }
      const destroyedTimes: number[] = [];
      if (entity.classname === 'func_breakable' && this.timeline?.temp_effects.length) {
        const threshold = THREE.MathUtils.clamp(
          Math.ceil(Number(prop(entity, 'health') ?? 1) / 25), 1, 5,
        );
        const impacts = new Map<number, number>();
        for (const effect of this.timeline.temp_effects) {
          const points = [effect.origin, effect.end].map((point) => new THREE.Vector3(
            point.x * .01, point.z * .01, -point.y * .01,
          ));
          if (!points.some((point) =>
            Math.abs(point.x - center.x) <= extent.x / 2 + .18
            && Math.abs(point.y - center.y) <= extent.y / 2 + .18
            && Math.abs(point.z - center.z) <= extent.z / 2 + .18)) continue;
          const round = this.roundIndexAt(effect.time);
          if (destroyedTimes.some((time) => this.roundIndexAt(time) === round)) continue;
          const count = (impacts.get(round) ?? 0) + 1;
          impacts.set(round, count);
          if (count >= threshold) destroyedTimes.push(effect.time);
        }
      }
      this.dynamicBrushes.push({
        pivot, mesh, entity, kind: entity.classname, base: origin.clone(),
        boundsCenter: center.clone(), extent, path, destroyedTimes,
      });
    }

    // A bounded set of BSP point lights gives unlit props and viewmodels
    // useful local contrast while baked lightmaps remain authoritative.
    let lightCount = 0;
    for (const entity of bsp.entities) {
      if (!/^light($|_)/.test(entity.classname) || !entity.origin || lightCount >= 24) continue;
      const lightValue = prop(entity, '_light') ?? prop(entity, 'light') ?? '255 240 210 180';
      const values = lightValue.split(/\s+/).map(Number);
      const color = new THREE.Color(
        (values[0] ?? 255) / 255,
        (values[1] ?? values[0] ?? 255) / 255,
        (values[2] ?? values[0] ?? 255) / 255,
      );
      const intensity = THREE.MathUtils.clamp((values[3] ?? values[0] ?? 180) / 255, .18, 1.15);
      const light = new THREE.PointLight(color, intensity, 7.5, 1.8);
      light.position.set(entity.origin.x * .01, entity.origin.z * .01, -entity.origin.y * .01);
      root.add(light);
      lightCount++;
    }
    this.mapMesh = root;
    this.scene!.add(root);

    // Update UI
    this.dropOverlay.classList.add('hidden');
    this.mapNameEl.textContent = name;

    // Position camera
    const center = new THREE.Vector3(
      (bsp.bounds_min.x + bsp.bounds_max.x) / 2,
      (bsp.bounds_min.y + bsp.bounds_max.y) / 2,
      (bsp.bounds_min.z + bsp.bounds_max.z) / 2
    );
    const size = Math.max(
      bsp.bounds_max.x - bsp.bounds_min.x,
      bsp.bounds_max.y - bsp.bounds_min.y,
      bsp.bounds_max.z - bsp.bounds_min.z
    );

    this.controls!.target.copy(center);
    this.camera!.position.set(center.x + size * 0.5, center.y + size * 0.5, center.z + size * 0.5);
  }

  private updateDynamicMapEntities(states: PlayerState[]): void {
    if (!this.dynamicBrushes.length && !this.animatedMapMaterials.length) return;
    const property = (entity: BspEntity, key: string) =>
      entity.properties.find(([name]) => name === key)?.[1];
    const playerPositions = states.map((state) => new THREE.Vector3(
      state.origin.x * .01, state.origin.z * .01, -state.origin.y * .01,
    ));
    for (const material of this.animatedMapMaterials) {
      if (material.map) {
        material.map.offset.set(this.currentTime * .018, Math.sin(this.currentTime * .35) * .012);
        material.map.needsUpdate = true;
      }
    }
    for (const brush of this.dynamicBrushes) {
      const flags = Number(property(brush.entity, 'spawnflags') ?? 0);
      const speed = Math.max(1, Number(property(brush.entity, 'speed') ?? 100));
      const closest = playerPositions.length
        ? Math.min(...playerPositions.map((point) => point.distanceTo(brush.base)))
        : Infinity;
      brush.pivot.position.copy(brush.base);
      brush.pivot.rotation.set(0, 0, 0);

      if (brush.kind === 'func_breakable') {
        const round = this.roundIndexAt(this.currentTime);
        brush.mesh.visible = !brush.destroyedTimes.some((time) =>
          time <= this.currentTime && this.roundIndexAt(time) === round);
      } else if (brush.kind === 'func_rotating') {
        if (!(flags & 1)) continue;
        const radians = THREE.MathUtils.degToRad(speed * this.currentTime * ((flags & 2) ? -1 : 1));
        // GoldSrc X/Y axis flags map to Three X/-Z; default is vertical Z -> Y.
        if (flags & 4) brush.pivot.rotation.x = radians;
        else if (flags & 8) brush.pivot.rotation.z = -radians;
        else brush.pivot.rotation.y = radians;
      } else if (brush.kind === 'func_train' || brush.kind === 'func_tracktrain') {
        const points = [brush.base, ...brush.path];
        if (points.length < 2) continue;
        const segments: Array<{ from: THREE.Vector3; to: THREE.Vector3; length: number }> = [];
        let total = 0;
        for (let index = 0; index < points.length - 1; index++) {
          const length = points[index].distanceTo(points[index + 1]);
          if (length > .001) { segments.push({ from: points[index], to: points[index + 1], length }); total += length; }
        }
        if (!segments.length || total <= 0) continue;
        let distance = (this.currentTime * speed * .01) % total;
        for (const segment of segments) {
          if (distance <= segment.length) {
            brush.pivot.position.lerpVectors(segment.from, segment.to, distance / segment.length);
            break;
          }
          distance -= segment.length;
        }
      } else if (/^func_door/.test(brush.kind)) {
        const open = 1 - THREE.MathUtils.smoothstep(closest, .55, 1.15);
        if (brush.kind === 'func_door_rotating') {
          const sign = flags & 2 ? -1 : 1;
          brush.pivot.rotation.y = THREE.MathUtils.degToRad(90 * open * sign);
          continue;
        }
        const angle = Number(property(brush.entity, 'angle') ?? 0);
        const direction = angle === -1 ? new THREE.Vector3(0, 1, 0)
          : angle === -2 ? new THREE.Vector3(0, -1, 0)
            : new THREE.Vector3(
              Math.cos(THREE.MathUtils.degToRad(angle)),
              0,
              -Math.sin(THREE.MathUtils.degToRad(angle)),
            );
        const lip = Number(property(brush.entity, 'lip') ?? 8) * .01;
        const travel = Math.max(.05,
          Math.abs(direction.x) * brush.extent.x
          + Math.abs(direction.y) * brush.extent.y
          + Math.abs(direction.z) * brush.extent.z - lip);
        brush.pivot.position.addScaledVector(direction, travel * open);
      } else if (brush.kind === 'func_plat') {
        const travel = Math.max(.1, brush.extent.y - Number(property(brush.entity, 'lip') ?? 8) * .01);
        const active = 1 - THREE.MathUtils.smoothstep(closest, .65, 1.25);
        brush.pivot.position.y = brush.base.y + travel * active;
      } else if (brush.kind === 'func_button') {
        const pressed = 1 - THREE.MathUtils.smoothstep(closest, .42, .85);
        const angle = THREE.MathUtils.degToRad(Number(property(brush.entity, 'angle') ?? 0));
        brush.pivot.position.add(new THREE.Vector3(Math.cos(angle), 0, -Math.sin(angle)).multiplyScalar(-.035 * pressed));
      }
    }
  }

  private async tryAutoLoadMap(mapName: string): Promise<void> {
    const path = `maps/${mapName}.bsp`;
    try {
      const response = await fetch(path);
      if (response.ok) {
        const data = await response.arrayBuffer();
        if (data.byteLength < 4 || new DataView(data).getInt32(0, true) !== 30) {
          this.reportMissingAsset(path);
          this.showAnnouncement(`Map unavailable · load ${mapName}.bsp`, '#ffb36b');
          return;
        }
        await this.loadBSPData(data, mapName);
        return;
      }
      this.reportMissingAsset(path);
      this.showAnnouncement(`Map unavailable · load ${mapName}.bsp`, '#ffb36b');
    } catch {
      this.reportMissingAsset(path);
      this.showAnnouncement(`Map unavailable · load ${mapName}.bsp`, '#ffb36b');
    }
  }

  private togglePlayback(): void {
    if (!this.timeline) return;

    this.isPlaying = !this.isPlaying;
    this.updateUI();

    if (this.isPlaying) {
      this.lastFrameTime = performance.now();
      this.schedulePlaybackPreload();
    }
  }

  private advancePlayback(now: number): void {
    if (!this.isPlaying || !this.timeline) return;

    const deltaTime = (now - this.lastFrameTime) / 1000 * this.playbackSpeed;
    this.lastFrameTime = now;

    this.currentTime += deltaTime;
    this.finishKillReplayIfNeeded();

    // Guard against invalid duration
    if (this.duration <= 0) {
      console.error('Invalid duration:', this.duration);
      this.isPlaying = false;
      this.updateUI();
      return;
    }

    if (this.currentTime >= this.duration) {
      this.currentTime = this.duration;
      this.isPlaying = false;
      this.updateUI();
      return;
    }

    try {
      this.updatePlayback();
      this.displayEventsUpToTime(this.currentTime);
    } catch (e) {
      console.error('Error in updatePlayback:', e);
    }
  }

  private updatePlayback(): void {
    if (!this.timeline || this.duration <= 0) return;

    const playerStates = interpolateSoa(this.timeline, this.currentTime, this.playbackMode);
    const SCALE = 0.01;

    const deaths = this.computeDeaths(this.currentTime);
    const statesByName = new Map<string, PlayerState>();
    const followedPlayerState = this.followTarget && this.followTarget !== 'Spectator Camera'
      ? playerStates.find((state) => state.name === this.followTarget)
      : null;
    this.updateDirector();

    // Update each player mesh based on their state from the timeline
    for (const state of playerStates) {
      const rostered = this.players.some((player) => player.name === state.name);
      if (this.players.length > 0 && !rostered && /^Player \d+$/.test(state.name)) {
        // HLTV streams can carry an entity update for an unregistered proxy or
        // spectator slot. The parser gives it a synthetic name, but without
        // userinfo there is no authoritative team, skin, or weapon to render.
        const synthetic = this.playerMeshes.get(state.name);
        if (synthetic) synthetic.visible = false;
        continue;
      }
      statesByName.set(state.name, state);
      // Convert GoldSrc coordinates to Three.js coordinates
      // GoldSrc: X=forward, Y=left, Z=up
      // Three.js: X=right, Y=up, Z=forward
      const x = state.origin.x * SCALE;
      const y = state.origin.z * SCALE;  // GoldSrc Z -> Three.js Y (up)
      const z = -state.origin.y * SCALE; // GoldSrc Y -> Three.js -Z

      // Find mesh by player name
      let mesh = this.playerMeshes.get(state.name);

      // If no specific mesh found, check if this is the recorder
      if (!mesh && state.name === 'Recorder' && this.playerMesh) {
        mesh = this.playerMesh;
      }

      // If still no mesh, create one dynamically
      if (!mesh) {
        mesh = this.createSinglePlayerMesh(this.teamColorFor(state.name));
        mesh.userData.playerName = state.name;
        this.scene!.add(mesh);
        this.playerMeshes.set(state.name, mesh);
      }

      this.lastSeen.set(state.name, this.currentTime);
      this.recolorPlayerMesh(mesh, this.teamColorFor(state.name));
      const model = this.modelAt(state.name, this.currentTime);
      if (model) {
        this.applySkin(mesh, model);
        this.applyWeapon(mesh, `${model}|${this.weaponFor(state.name, state.weapon)}`);
      }

      // Animate: run cycle when moving, idle otherwise (baked frames)
      const prevPos = mesh.userData.animPos as THREE.Vector3 | undefined;
      const prevT = mesh.userData.animT as number | undefined;
      const newPos = new THREE.Vector3(x, y, z);
      const reportedSpeed = state.velocity
        ? Math.hypot(state.velocity.x, state.velocity.y)
        : 0;
      let moving = reportedSpeed > 70;
      const animDt = prevT === undefined ? 0 : this.currentTime - prevT;
      if (!moving && prevPos && animDt > 0 && animDt < 0.5) {
        const measuredSpeed = prevPos.distanceTo(newPos) / animDt;
        // Some demos omit usable velocity values even while origins change.
        // The rendered coordinates are scaled by 0.01, hence 0.7 here is
        // equivalent to roughly 70 GoldSrc units per second.
        moving = measuredSpeed > 0.7;
      }
      mesh.userData.animPos = newPos;
      mesh.userData.animT = this.currentTime;
      const pivotForAnim = mesh.getObjectByName('yawPivot');
      const skinGroup = pivotForAnim?.getObjectByName('skin') as THREE.Group | undefined;
      const labels = skinGroup?.userData.seqLabels as string[] | undefined;
      const sequenceLabel = labels?.[state.sequence ?? 0] ?? '';
      const gaitLabel = labels?.[state.gait ?? 0] ?? '';
      const actionSequence =
        /die|death|shoot|attack|fire|reload|jump|hop|leap|swim|plant|defuse|throw|grenade|flinch|hit/i
          .test(sequenceLabel);
      // GoldSrc sends the main sequence frame, but advances gait (run/walk)
      // separately on the client. Applying the main frame to a baked run
      // animation freezes moving players in a single pose. Prefer gait labels
      // for locomotion and let replay time advance those cycles.
      const recordedLabel = actionSequence
        ? sequenceLabel
        : gaitLabel || sequenceLabel;
      const recordedFrame = actionSequence ? state.frame : undefined;
      if (skinGroup) this.tickSkinAnimation(skinGroup, moving, recordedLabel, recordedFrame);
      const weaponGroup = pivotForAnim?.getObjectByName('weapon') as THREE.Group | undefined;
      if (weaponGroup) this.tickSkinAnimation(weaponGroup, moving, recordedLabel, recordedFrame);
      const noDraw = !!((state.effects ?? 0) & 128);
      // Do not let another world model enter the first-person camera hull.
      // GoldSrc resolves this through player collision; sparse demo samples
      // can briefly overlap and otherwise fill the screen with clipped limbs.
      const cameraHullOverlap = !!followedPlayerState
        && state.name !== followedPlayerState.name
        && Math.hypot(
          state.origin.x - followedPlayerState.origin.x,
          state.origin.y - followedPlayerState.origin.y,
          state.origin.z - followedPlayerState.origin.z,
        ) < 40;
      mesh.visible = !noDraw && !deaths.has(state.name)
        && this.followTarget !== state.name && !cameraHullOverlap;
      mesh.position.set(x, y, z);

      // GoldSrc yaw 0 = +X, counter-clockwise. Mapped to Three.js (Z = -GoldSrc Y),
      // the pivot's +Z forward lines up at rotation.y = yaw + 90 degrees.
      const pivot = mesh.getObjectByName('yawPivot');
      if (pivot) {
        pivot.rotation.y = THREE.MathUtils.degToRad(state.angles.y + 90);
      }
    }

    // Hide meshes for players absent from the entity stream (disconnects,
    // parser dropouts) instead of freezing them at their last position.
    for (const [name, mesh] of this.playerMeshes) {
      if (statesByName.has(name)) continue;
      const seen = this.lastSeen.get(name);
      const stale = seen === undefined
        || this.currentTime - seen > 4
        || seen > this.currentTime + 0.5; // seeked backwards past last sighting
      if (stale) mesh.visible = false;
    }

    this.updateDeathMarkers(deaths);
    this.updateDynamicMapEntities(playerStates);
    this.updateObjects();
    this.updateRecordedEffects();
    this.updateFx();
    this.updateShots();
    this.updateNetworkSounds();
    this.updateRecordedSounds();
    this.updateFallbackAudio(playerStates, deaths);
    this.updateBombIndicator();
    this.updateFollowCamera(statesByName, deaths);
    this.updatePlayerHud(playerStates);
    this.updateRecordedScreenFade();
    this.updateTacticalTracks(playerStates);
    this.updateEconomyStrip();
    this.updateRoundIndicator();
    this.renderPlayerList(deaths, playerStates);

    // The progress bar is compositor-driven and the text/HUD clock only need
    // a 10 Hz refresh. Rewriting layout-bound DOM on every display frame can
    // otherwise create a small but visible periodic hitch.
    const timelineTick = Math.floor(this.currentTime * 10);
    if (timelineTick !== this.timelineUiTick) {
      this.timelineUiTick = timelineTick;
      const progress = Math.min(1, this.currentTime / this.duration);
      this.timelineProgress.style.transform = `scaleX(${progress})`;
      this.timeDisplay.textContent = `${this.formatTime(this.currentTime)} / ${this.formatTime(this.duration)}`;
      this.updateRoundTimer(this.currentTime);
    }
    const statsPanel = document.getElementById('stats-panel');
    if (statsPanel && statsPanel.dataset.second !== String(Math.floor(this.currentTime))) {
      statsPanel.dataset.second = String(Math.floor(this.currentTime));
      this.renderStatsPanel();
    }
    this.updateDiagnostics();
    if (this.isPlaying) this.schedulePlaybackPreload();
  }

  private seekTo(percent: number): void {
    this.seekToTime(percent * this.duration);
  }

  private seekRelative(seconds: number): void {
    this.seekToTime(this.currentTime + seconds);
  }

  private seekToTime(time: number): void {
    if (!this.timeline) return;
    this.currentTime = Math.max(0, Math.min(this.duration, time));
    this.timelineUiTick = -1;
    this.resetEventFeed();
    this.stopActiveAudio();
    this.displayEventsUpToTime(this.currentTime);
    this.smoothedEye = null;
    this.smoothedForward = null;
    this.cameraSmoothWallTime = performance.now();
    this.lastSeen.clear();
    this.playerTrails.clear();
    this.tacticalLastSample = -Infinity;
    this.clearRecordedFx();
    for (const mesh of this.playerMeshes.values()) {
      mesh.traverse((object) => {
        object.userData.frame = -1;
        object.userData.animName = undefined;
        object.userData.transitionFrom = undefined;
      });
    }
    this.updatePlayback();
    void this.preloadNearTime(this.currentTime);
  }

  private schedulePlaybackPreload(): void {
    if (
      !this.timeline
      || this.preloadScheduled
      || Math.abs(this.currentTime - this.lastPreloadTime) < 1.5
    ) return;
    this.preloadScheduled = true;
    this.lastPreloadTime = this.currentTime;
    const preloadTime = Math.min(this.duration, this.currentTime + 2.5);
    const run = () => {
      this.preloadScheduled = false;
      void this.preloadNearTime(preloadTime, true);
    };
    const requestIdle = window.requestIdleCallback?.bind(window);
    if (requestIdle) {
      requestIdle(run, { timeout: 600 });
    } else {
      window.setTimeout(run, 0);
    }
  }

  private idlePreloadYield(): Promise<void> {
    return new Promise((resolve) => {
      const requestIdle = window.requestIdleCallback?.bind(window);
      if (requestIdle) requestIdle(() => resolve(), { timeout: 350 });
      else window.setTimeout(resolve, 0);
    });
  }

  private async preloadNearTime(time: number, stagger = false): Promise<void> {
    const demo = this.timeline;
    if (!demo) return;
    const states = interpolateSoa(demo, time, this.playbackMode);
    const models = new Set<string>();
    for (const state of states) {
      const playerModel = this.modelAt(state.name, time);
      if (!playerModel) continue;
      models.add(playerModel);
      models.add(`${playerModel}|${this.weaponFor(state.name, state.weapon)}`);
    }
    const modelNames = [...models].slice(0, 24);

    const audioLoads: Array<Promise<AudioBuffer | null>> = [];
    if (this.soundOn && this.audioCtx) {
      const samples = new Set<string>();
      for (const sound of demo.network_sounds) {
        if (sound.time < time - 0.25) continue;
        if (sound.time > time + 2.5 || samples.size >= 16) break;
        samples.add(sound.sample);
      }
      for (const sample of samples) audioLoads.push(this.loadRecordedSound(sample));
    }
    if (stagger) {
      // MDL parsing and geometry creation are synchronous once bytes arrive.
      // Let at most one model consume an idle slice so a group of future
      // weapon/player changes cannot monopolize a display frame.
      for (const model of modelNames) {
        await this.loadPlayerModelTemplate(model);
        await this.idlePreloadYield();
      }
      await Promise.allSettled(audioLoads);
    } else {
      await Promise.allSettled([
        ...modelNames.map((model) => this.loadPlayerModelTemplate(model)),
        ...audioLoads,
      ]);
    }
  }

  private async runAssetPreflight(): Promise<void> {
    const demo = this.timeline;
    const status = document.getElementById('asset-status');
    if (!demo || !status) return;
    status.textContent = 'CHECKING DEMO ASSETS…';
    status.classList.remove('hidden');
    const models = new Set<string>();
    for (const player of this.players) if (player.model) models.add(player.model);
    for (const changes of this.modelTimeline.values()) {
      for (const [, model] of changes) if (model) models.add(model);
    }
    for (const [, model] of demo.model_names) {
      const base = model.replace(/^models\//i, '').replace(/\.mdl$/i, '').split('/').pop() ?? '';
      if (/^[pvw]_/.test(base)) models.add(base);
    }
    const sounds = [...new Set(demo.network_sounds.map((sound) =>
      sound.sample.replace(/^sound\//i, '').replace(/^\/+/, '')))]
      .filter((sample) => sample && !sample.includes('..') && /^[a-z0-9_./-]+$/i.test(sample));
    const before = this.missingAssets.size;
    const tasks: Array<() => Promise<void>> = [];
    for (const model of models) tasks.push(async () => { await this.fetchMdl(model); });
    for (const sample of sounds) tasks.push(async () => {
      const path = `sounds/${sample}`;
      try {
        const response = await fetch(path);
        if (!response.ok) { this.reportMissingAsset(path); return; }
        const bytes = new Uint8Array(await response.arrayBuffer());
        if (bytes.length < 12 || String.fromCharCode(...bytes.subarray(0, 4)) !== 'RIFF') {
          this.reportMissingAsset(path);
        }
      } catch {
        this.reportMissingAsset(path);
      }
    });
    let cursor = 0;
    const workers = Array.from({ length: Math.min(8, tasks.length) }, async () => {
      while (cursor < tasks.length) {
        const task = tasks[cursor++];
        await task();
      }
    });
    await Promise.all(workers);
    const missing = this.missingAssets.size - before;
    this.assetPreflight = { checked: tasks.length, missing, models: models.size, sounds: sounds.length };
    if (missing === 0) {
      status.textContent = `ASSET PREFLIGHT PASSED · ${tasks.length} CHECKED`;
      status.title = `${models.size} models · ${sounds.length} sounds`;
      window.setTimeout(() => {
        if (this.assetPreflight?.missing === 0) status.classList.add('hidden');
      }, 3500);
    }
    this.updateDiagnostics(true);
  }

  private updateUI(): void {
    this.playBtn.textContent = this.isPlaying ? 'Pause' : 'Play';
  }

  private runReplayVerification(): void {
    if (!this.timeline) return;
    this.verificationReport = verifyReplay(this.timeline);
    const button = document.getElementById('diagnostics-btn');
    if (button) {
      button.dataset.status = this.verificationReport.status;
      button.setAttribute(
        'aria-label',
        `Replay verification: ${this.verificationReport.status}. Open diagnostics`,
      );
      button.title = `Replay ${this.verificationReport.status} · ${this.verificationReport.checksum} (D)`;
    }
    console.info('Replay verification', this.verificationReport);
    this.updateDiagnostics(true);
  }

  private toggleDiagnostics(): void {
    this.setDiagnosticsVisible(!this.diagnosticsVisible);
  }

  private setDiagnosticsVisible(visible: boolean): void {
    this.diagnosticsVisible = visible;
    document.getElementById('diagnostics-panel')?.classList.toggle('hidden', !visible);
    document.getElementById('diagnostics-btn')?.classList.toggle('active', visible);
    if (visible) this.updateDiagnostics(true);
  }

  private diagnosticsStateHtml(): string {
    if (!this.timeline) return '<div class="diagnostics-empty">Load a demo to inspect replay state.</div>';

    const window = sampleWindowAt(this.timeline, this.currentTime);
    const states = interpolateSoa(this.timeline, this.currentTime);
    const selectedName = this.followTarget && this.followTarget !== 'Spectator Camera'
      ? this.followTarget
      : null;
    const selected = selectedName
      ? states.find((state) => state.name === selectedName)
      : null;
    const pov = this.followTarget === 'Spectator Camera'
      ? this.povSampleAt(this.currentTime)
      : null;
    const state = pov ?? selected;
    const source = pov
      ? 'POV camera track'
      : selected
        ? 'Entity timeline'
        : 'Free camera';
    const sampleGap = window.nextTime - window.time;
    const drift = this.currentTime - window.time;
    const position = state
      ? `${state.origin.x.toFixed(2)}, ${state.origin.y.toFixed(2)}, ${state.origin.z.toFixed(2)}`
      : '—';
    const angles = state
      ? `${state.angles.x.toFixed(2)}°, ${state.angles.y.toFixed(2)}°`
      : '—';
    const camera = this.camera
      ? `${this.camera.position.x.toFixed(2)}, ${this.camera.position.y.toFixed(2)}, ${this.camera.position.z.toFixed(2)}`
      : '—';
    const effectKinds = [...new Set(this.timeline.temp_effects.map((effect) => effect.kind))].sort((a, b) => a - b);
    const eventKinds = [...new Set(this.timeline.events.map((event) => event.event_type))];
    const coverage = [
      this.timeline.povTimes.length ? 'POV' : null,
      this.timeline.objTimes.length ? 'objects' : null,
      this.timeline.shotTimes.length ? 'shots' : null,
      this.timeline.weaponAnimTimes.length ? 'weapon animations' : null,
      this.timeline.network_sounds.length ? 'spatial audio' : null,
      this.timeline.player_stats.length ? 'score stats' : null,
    ].filter(Boolean).join(', ') || 'entity timeline only';

    return `
      <div class="diagnostics-section-label">Live replay state</div>
      <div class="diagnostics-grid">
        <span>Demo time</span><strong>${this.currentTime.toFixed(3)}s</strong>
        <span>Timeline sample</span><strong>${window.index.toLocaleString()} → ${window.nextIndex.toLocaleString()}</strong>
        <span>Sample times</span><strong>${window.time.toFixed(3)}s → ${window.nextTime.toFixed(3)}s</strong>
        <span>Interpolation</span><strong>${(window.interpolation * 100).toFixed(1)}%</strong>
        <span>Offset / gap</span><strong>${drift.toFixed(3)}s / ${sampleGap.toFixed(3)}s</strong>
        <span>Visible entities</span><strong>${states.length} / ${this.timeline.slot_names.length}</strong>
        <span>Event cursor</span><strong>${Math.max(0, this.lastDisplayedEventIndex + 1)} / ${this.timeline.events.length}</strong>
        <span>View source</span><strong>${this.escapeHtml(source)}</strong>
        <span>Target</span><strong>${this.escapeHtml(this.followTarget ?? 'Free camera')}</strong>
        <span>Raw origin</span><strong>${position}</strong>
        <span>Raw pitch / yaw</span><strong>${angles}</strong>
        <span>Render camera</span><strong>${camera}</strong>
      </div>
      <div class="diagnostics-section-label">Parser data coverage</div>
      <div class="diagnostics-grid">
        <span>Processed tracks</span><strong>${coverage}</strong>
        <span>Event families</span><strong>${eventKinds.length} · ${eventKinds.join(', ')}</strong>
        <span>Temp-effect kinds</span><strong>${effectKinds.length ? effectKinds.join(', ') : 'none recorded'}</strong>
        <span>HUD messages</span><strong>${this.timeline.hudTimes.length.toLocaleString()}</strong>
        <span>Observer updates</span><strong>${this.timeline.observerTimes.length.toLocaleString()}</strong>
        <span>Network sounds</span><strong>${this.timeline.network_sounds.length.toLocaleString()}</strong>
        <span>Asset preflight</span><strong>${this.assetPreflight
          ? `${this.assetPreflight.checked} checked · ${this.assetPreflight.missing} missing`
          : 'running / not yet run'}</strong>
        <span>Map dynamics</span><strong>${this.dynamicBrushes.length} brush models · ${this.animatedMapMaterials.length} animated surfaces</strong>
      </div>
    `;
  }

  private verificationHtml(report: ReplayVerificationReport): string {
    const statusLabel = report.status === 'pass'
      ? 'Deterministic'
      : report.status === 'warning'
        ? 'Review recommended'
        : 'Verification failed';
    const issues = report.issues.length
      ? `<div class="diagnostics-issues">${report.issues.map((issue) => `
          <div class="diagnostics-issue ${issue.severity}">
            <span>${issue.severity === 'error' ? '×' : '!'}</span>
            <p><strong>${this.escapeHtml(issue.code)}</strong>${this.escapeHtml(issue.message)}</p>
          </div>
        `).join('')}</div>`
      : '<div class="diagnostics-clean"><span>✓</span> Timeline structure, determinism, and seek equivalence passed.</div>';
    const checkpoints = report.checkpoints.map((checkpoint) => `
      <tr>
        <td>${checkpoint.time.toFixed(3)}s</td>
        <td>${checkpoint.sampleIndex.toLocaleString()}</td>
        <td>${checkpoint.players}</td>
        <td><code>${checkpoint.hash}</code></td>
        <td class="${checkpoint.seekEquivalent ? 'check-pass' : 'check-fail'}">${checkpoint.seekEquivalent ? 'match' : 'mismatch'}</td>
      </tr>
    `).join('');

    return `
      <div class="diagnostics-verdict ${report.status}">
        <span class="diagnostics-verdict-dot"></span>
        <div><strong>${statusLabel}</strong><small>Replay checksum ${report.checksum}</small></div>
        <em>${report.elapsedMs.toFixed(1)} ms</em>
      </div>
      <div class="diagnostics-section-label">Coverage</div>
      <div class="diagnostics-metrics">
        <div><strong>${report.stats.samples.toLocaleString()}</strong><span>samples</span></div>
        <div><strong>${report.stats.events.toLocaleString()}</strong><span>events</span></div>
        <div><strong>${report.stats.povSamples.toLocaleString()}</strong><span>POV</span></div>
        <div><strong>${report.stats.objectSamples.toLocaleString()}</strong><span>objects</span></div>
        <div><strong>${report.stats.shots.toLocaleString()}</strong><span>shots</span></div>
        <div><strong>${report.stats.weaponAnimations.toLocaleString()}</strong><span>weapon anims</span></div>
        <div><strong>${report.stats.sounds.toLocaleString()}</strong><span>sounds</span></div>
      </div>
      ${issues}
      <div class="diagnostics-section-label">Seek-equivalence checkpoints</div>
      <div class="diagnostics-table-wrap">
        <table class="diagnostics-table">
          <thead><tr><th>Time</th><th>Sample</th><th>Players</th><th>Hash</th><th>Linear vs seek</th></tr></thead>
          <tbody>${checkpoints}</tbody>
        </table>
      </div>
    `;
  }

  private updateDiagnostics(force = false): void {
    if (!this.diagnosticsVisible && !force) return;
    const now = performance.now();
    if (!force && now - this.diagnosticsLastRender < 100) return;
    this.diagnosticsLastRender = now;

    const live = document.getElementById('diagnostics-live');
    const verification = document.getElementById('diagnostics-verification');
    if (live) live.innerHTML = this.diagnosticsStateHtml();
    if (verification && (force || !verification.childElementCount)) {
      verification.innerHTML = this.verificationReport
        ? this.verificationHtml(this.verificationReport)
        : '<div class="diagnostics-empty">Verification has not run yet.</div>';
    }
  }

  private formatTime(seconds: number): string {
    if (!Number.isFinite(seconds) || seconds < 0) return '--:--';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }

  /// Team-grouped live roster: CT and T sections, alive/dead state, K/D.
  /// Rebuilt only when its content signature changes.
  private renderPlayerList(deaths?: Map<string, number>, states?: PlayerState[]): void {
    if (this.players.length === 0) {
      this.playerListPanel.classList.add('hidden');
      return;
    }
    this.playerListPanel.classList.remove('hidden');

    const dead = deaths ?? new Map<string, number>();
    const byName = new Map((states ?? []).map((state) => [state.name, state]));
    const groups: Record<string, PlayerInfo[]> = { CT: [], T: [], other: [] };
    for (const p of [...this.players].sort((a, b) => a.index - b.index)) {
      const team = this.teamAt(p.name, this.currentTime) ?? this.teamOf(p);
      groups[team === 'CT' ? 'CT' : team === 'T' ? 'T' : 'other'].push(p);
    }

    // Cheap change detection so this can run every frame
    const sig = [
      ...['CT', 'T', 'other'].map((t) => groups[t].map((p) => p.name).join('|')),
      [...dead.keys()].sort().join('|'),
      [...this.killCounts.entries()].map(([n, r]) => `${n}${r.k}${r.d}`).join('|'),
      this.players.map((player) => {
        const state = byName.get(player.name);
        return `${player.name}:${state?.health ?? -1}:${state?.weapon ?? 0}`;
      }).join('|'),
      this.followTarget ?? '',
    ].join('#');
    if (sig === this.rosterSignature) return;
    this.rosterSignature = sig;

    this.playersEl.innerHTML = '';
    const addEntry = (player: PlayerInfo) => {
      const entry = document.createElement('div');
      entry.className = 'player-entry';
      if (dead.has(player.name)) entry.classList.add('dead');
      if (this.followTarget === player.name) entry.classList.add('following');
      entry.dataset.name = player.name;
      entry.title = "Click to view from this player's eyes (Esc: free camera)";
      entry.addEventListener('click', () => {
        this.setFollowTarget(this.followTarget === player.name ? null : player.name);
      });

      const dot = document.createElement('div');
      dot.className = 'player-dot';
      const team = this.teamAt(player.name, this.currentTime);
      if (team === 'CT') dot.classList.add('ct');
      else if (team === 'T') dot.classList.add('t');

      const name = document.createElement('span');
      name.className = 'player-name';
      name.textContent = player.name;

      const kd = document.createElement('span');
      kd.className = 'player-kd';
      const r = this.killCounts.get(player.name);
      kd.textContent = r ? `${r.k}/${r.d}` : '';

      entry.appendChild(dot);
      entry.appendChild(name);
      entry.appendChild(kd);
      this.playersEl.appendChild(entry);
    };

    for (const [key, label] of [['CT', 'COUNTER-TERRORISTS'], ['T', 'TERRORISTS'], ['other', 'OTHER']] as const) {
      if (!groups[key].length) continue;
      const section = document.createElement('div');
      section.className = 'team-section';
      const header = document.createElement('div');
      header.className = `team-header ${key === 'CT' ? 'ct' : key === 'T' ? 't' : ''}`;
      header.textContent = label;
      section.appendChild(header);
      this.playersEl.appendChild(section);
      for (const p of groups[key]) addEntry(p);
    }

    // POV demos: offer the recorder's exact first-person view
    if (this.timeline?.povTimes.length) {
      const entry = document.createElement('div');
      entry.className = 'player-entry';
      entry.dataset.name = 'Spectator Camera';
      if (this.followTarget === 'Spectator Camera') entry.classList.add('following');
      entry.title = "The recording player's exact view (full frame rate)";
      const name = document.createElement('span');
      name.className = 'player-name';
      name.textContent = '📹 POV (recorder)';
      entry.appendChild(name);
      entry.addEventListener('click', () => {
        this.setFollowTarget(this.followTarget === 'Spectator Camera' ? null : 'Spectator Camera');
      });
      this.playersEl.appendChild(entry);
    }

    const compact = document.getElementById('spectator-roster');
    if (!compact) return;
    compact.classList.toggle('hidden', !this.followTarget || this.hudMode === 'off' || this.hudMode === 'broadcast');
    if (!this.followTarget || this.hudMode === 'off' || this.hudMode === 'broadcast') return;
    if (!states) {
      for (const state of interpolateSoa(this.timeline!, this.currentTime, this.playbackMode)) {
        byName.set(state.name, state);
      }
    }
    const renderCompactTeam = (team: 'CT' | 'T') => {
      const members = groups[team];
      if (!members.length) return '';
      const alive = members.filter((player) => !dead.has(player.name)).length;
      const rows = members.map((player) => {
        const isDead = dead.has(player.name);
        const state = byName.get(player.name);
        const health = isDead ? 'DEAD' : state?.health != null ? `${Math.max(0, state.health)} HP` : 'ALIVE';
        return `<button class="spectator-player${isDead ? ' dead' : ''}${this.followTarget === player.name ? ' active' : ''}"`
          + ` data-player="${this.escapeHtml(player.name)}"${isDead ? ' disabled' : ''}`
          + ` title="View ${this.escapeHtml(player.name)}"><span class="spectator-player-dot"></span>`
          + `<span class="spectator-player-name">${this.escapeHtml(player.name)}</span>`
          + `<span class="spectator-player-health">${health}</span></button>`;
      }).join('');
      return `<section class="spectator-team ${team.toLowerCase()}"><div class="spectator-team-label">`
        + `<span>${team === 'CT' ? 'COUNTER-TERRORISTS' : 'TERRORISTS'}</span><span>${alive}/${members.length}</span>`
        + `</div>${rows}</section>`;
    };
    compact.innerHTML = renderCompactTeam('CT') + renderCompactTeam('T');
  }

  private createEventFeed(): void {
    if (this.killFeedEl) this.killFeedEl.innerHTML = '';
    this.lastDisplayedEventIndex = -1;
    this.killCounts.clear();
  }

  private resetScoreboard(): void {
    this.scoreCT = 0;
    this.scoreT = 0;
    this.updateScoreboard();
    this.scoreboardEl.classList.remove('hidden');
  }

  private updateScoreboard(): void {
    this.scoreCTEl.textContent = this.scoreCT.toString();
    this.scoreTEl.textContent = this.scoreT.toString();
  }

  private resetRoundTimer(): void {
    this.roundTimerBaseSeconds = null;
    this.roundTimerStartTime = 0;
    this.roundTimerValueEl.textContent = '--:--';
    this.roundTimerEl.classList.remove('hidden');
  }

  private setRoundTimerFromEvent(seconds: number, eventTime: number): void {
    this.roundTimerBaseSeconds = seconds;
    this.roundTimerStartTime = eventTime;
    this.updateRoundTimer(this.currentTime);
  }

  private setRoundTimerFallback(eventTime: number): void {
    this.roundTimerBaseSeconds = this.defaultRoundSeconds;
    this.roundTimerStartTime = eventTime;
    this.updateRoundTimer(this.currentTime);
  }

  private updateRoundTimer(nowTime: number): void {
    if (this.roundTimerBaseSeconds === null) {
      return;
    }
    const elapsed = Math.max(0, nowTime - this.roundTimerStartTime);
    const remaining = Math.max(0, Math.round(this.roundTimerBaseSeconds - elapsed));
    const mins = Math.floor(remaining / 60);
    const secs = remaining % 60;
    this.roundTimerValueEl.textContent = `${mins}:${secs.toString().padStart(2, '0')}`;
    this.roundTimerValueEl.classList.toggle('low', remaining <= 20);
  }

  private displayEventsUpToTime(time: number): void {
    if (!this.timeline?.events || !this.killFeedEl) return;

    const events = this.timeline.events;
    let startIndex = this.lastDisplayedEventIndex + 1;

    // Find events that should be displayed
    for (let i = startIndex; i < events.length; i++) {
      if (events[i].time <= time) {
        this.displayEvent(events[i]);
        this.lastDisplayedEventIndex = i;
      } else {
        break; // Events are sorted by time
      }
    }
  }

  /// Route a game event: state updates always apply; feed entries and
  /// announcements only show for events happening "live" (not seek catch-up).
  private displayEvent(event: GameEvent): void {
    const live = Math.abs(event.time - this.currentTime) < 4;

    switch (event.event_type) {
      case 'Kill': {
        const killer = event.data.killer || '???';
        const victim = event.data.victim || '???';
        this.bumpKD(killer, 'k');
        this.bumpKD(victim, 'd');
        if (event.data.weapon) this.lastWeapon.set(killer, event.data.weapon);
        if (live) {
          const kc = this.teamColorFor(killer, event.time).toString(16).padStart(6, '0');
          const vc = this.teamColorFor(victim, event.time).toString(16).padStart(6, '0');
          const hs = event.data.headshot
            ? ' <span class="hs" title="Headshot" aria-label="Headshot"><span aria-hidden="true">⊕</span><small>HS</small></span>'
            : '';
          this.pushKillEntry(
            `<span style="color:#${kc}">${this.escapeHtml(killer)}</span>` +
            ` <span class="weapon">${this.escapeHtml(event.data.weapon || '?')}${hs}</span> ` +
            `<span style="color:#${vc}">${this.escapeHtml(victim)}</span>`
          );
          if (event.data.killer && event.data.victim && Math.abs(event.time - this.currentTime) < 0.5) {
            this.spawnKillTracer(event.data.killer, event.data.victim);
          }
          this.switchAfterFollowedDeath(killer, victim);
        }
        break;
      }
      case 'Suicide': {
        const victim = event.data.victim || '???';
        this.bumpKD(victim, 'd');
        if (live) {
          const vc = this.teamColorFor(victim, event.time).toString(16).padStart(6, '0');
          this.pushKillEntry(`<span style="color:#${vc}">${this.escapeHtml(victim)}</span> <span class="weapon">died</span>`);
        }
        break;
      }
      case 'RoundStart':
        this.bombPlantedAt = null;
        this.setRoundTimerFallback(event.time);
        if (live) {
          this.showAnnouncement(`Round ${this.roundIndexAt(event.time) + 1}`, '#dde5f0');
          // updatePlayback runs before event dispatch, so refresh an open
          // scoreboard immediately instead of leaving stale flags for a frame.
          this.renderStatsPanel();
        }
        break;
      case 'RoundEnd': {
        const winner = event.data.winner || '???';
        if (winner === 'CT') this.scoreCT += 1;
        else if (winner === 'T') this.scoreT += 1;
        this.updateScoreboard();
        this.roundTimerBaseSeconds = 0;
        this.roundTimerStartTime = event.time;
        this.updateRoundTimer(event.time);
        if (live) {
          this.showAnnouncement(
            winner === 'CT' ? 'Counter-Terrorists Win' : winner === 'T' ? 'Terrorists Win' : 'Round Over',
            winner === 'CT' ? '#4fc3f7' : '#ffd54f'
          );
        }
        break;
      }
      case 'TeamScore':
        if (event.data.team && typeof event.data.score === 'number') {
          const team = event.data.team.toUpperCase();
          if (team.includes('CT') || team.includes('COUNTER')) this.scoreCT = event.data.score;
          else if (team.includes('T')) this.scoreT = event.data.score;
          this.updateScoreboard();
        }
        break;
      case 'RoundTime':
        if (typeof event.data.round_time === 'number') {
          this.setRoundTimerFromEvent(event.data.round_time, event.time);
        }
        break;
      case 'BombPlanted':
        this.bombPlantedAt = event.time;
        if (live) this.showAnnouncement('🔻 Bomb Planted', '#ff6b6b');
        break;
      case 'BombDefused':
        this.bombPlantedAt = null;
        if (live) this.showAnnouncement('Bomb Defused', '#4fc3f7');
        break;
      case 'BombExploded':
        this.bombPlantedAt = null;
        if (live) this.showAnnouncement('💥 Bomb Exploded', '#ff3333');
        break;
      case 'TextMessage': {
        const msg = event.data.message ?? '';
        // Chat lines only (SayText); skip server/localization noise
        const isChat = !!event.data.player || /.: ./.test(msg);
        if (live && isChat && !msg.startsWith('#')) {
          this.pushChatLine(msg, event.data.player);
        }
        break;
      }
      default:
        break; // ModelChange: state only
    }
  }

  private pushChatLine(message: string, player?: string): void {
    let feed = document.getElementById('chat-feed');
    if (!feed) {
      feed = document.createElement('div');
      feed.id = 'chat-feed';
      document.body.appendChild(feed);
    }
    const line = document.createElement('div');
    line.className = 'chat-line';
    const sep = message.indexOf(': ');
    if (sep > 0) {
      const who = message.slice(0, sep);
      const nameForColor = player ?? who.replace(/^\((CT|T|TEAM)\)\s*/i, '');
      const color = this.teamColorFor(nameForColor).toString(16).padStart(6, '0');
      line.innerHTML = `<span class="chat-name" style="color:#${color}">${this.escapeHtml(who)}</span>` +
        `<span style="color:#dde"> : ${this.escapeHtml(message.slice(sep + 2))}</span>`;
    } else {
      line.textContent = message;
      line.style.color = '#aab';
    }
    feed.appendChild(line);
    while (feed.children.length > 7) feed.removeChild(feed.firstChild!);
    window.setTimeout(() => {
      line.classList.add('fading');
      window.setTimeout(() => line.remove(), 900);
    }, 11000);
  }

  private bumpKD(name: string, which: 'k' | 'd'): void {
    let r = this.killCounts.get(name);
    if (!r) { r = { k: 0, d: 0 }; this.killCounts.set(name, r); }
    r[which]++;
  }

  private pushKillEntry(html: string): void {
    if (!this.killFeedEl) return;
    const entry = document.createElement('div');
    entry.className = 'kill-entry';
    entry.innerHTML = html;
    this.killFeedEl.appendChild(entry);
    while (this.killFeedEl.children.length > 6) {
      this.killFeedEl.removeChild(this.killFeedEl.firstChild!);
    }
    window.setTimeout(() => {
      entry.classList.add('fading');
      window.setTimeout(() => entry.remove(), 700);
    }, 6000);
  }

  private showAnnouncement(text: string, color: string): void {
    const el = document.getElementById('announcement');
    if (!el) return;
    window.clearTimeout(this.announceTimer);
    el.textContent = text;
    el.style.color = color;
    el.classList.remove('hidden', 'fading');
    this.announceTimer = window.setTimeout(() => {
      el.classList.add('fading');
      this.announceTimer = window.setTimeout(() => el.classList.add('hidden'), 800);
    }, 2600);
  }

  private resetEventFeed(): void {
    this.lastDisplayedEventIndex = -1;
    this.killCounts.clear();
    this.lastWeapon.clear();
    this.bombPlantedAt = null;
    if (this.killFeedEl) this.killFeedEl.innerHTML = '';
    const chat = document.getElementById('chat-feed');
    if (chat) chat.innerHTML = '';
    document.getElementById('announcement')?.classList.add('hidden');
    this.rosterSignature = '';
    this.resetScoreboard();
    this.resetRoundTimer();
    this.lastDemoSoundT = this.currentTime;
    this.lastNetworkSoundT = this.currentTime;
    this.lastFallbackAudioT = this.currentTime;
    this.nextFootstepAt.clear();
    this.lastTempEffectT = -1;
    this.lastShotT = this.currentTime;
    this.lastRenderedShotBySlot.clear();
  }
}

// Initialize and expose for debugging
(window as unknown as { demoPlayer: DemoPlayer }).demoPlayer = new DemoPlayer();
