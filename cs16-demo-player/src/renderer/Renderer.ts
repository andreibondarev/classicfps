import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { PlayerState } from '../parser/types.ts';
import { ParsedBSP } from '../bsp/types.ts';
import { BSPRenderer } from '../bsp/BSPRenderer.ts';

interface PlayerMesh {
  group: THREE.Group;
  body: THREE.Mesh;
  label: THREE.Sprite;
  labelText: string;
}

export class Renderer {
  private container: HTMLElement;
  private scene: THREE.Scene;
  private camera: THREE.PerspectiveCamera;
  private renderer: THREE.WebGLRenderer;
  private controls: OrbitControls;
  private playerMeshes: Map<number, PlayerMesh> = new Map();
  private ground: THREE.Mesh;
  private gridHelper: THREE.GridHelper;
  private mapGroup: THREE.Group | null = null;

  // Scale factor: CS units are roughly 1 unit = 1 inch, so 1 unit ≈ 0.0254m
  // We'll use a scale of 0.01 to make the scene manageable
  private readonly SCALE = 0.01;
  private readonly PLAYER_HEIGHT = 72 * this.SCALE; // ~72 units tall in CS
  private readonly PLAYER_RADIUS = 16 * this.SCALE; // ~16 units radius

  constructor(container: HTMLElement) {
    this.container = container;

    // Scene setup
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x1a1a2e);

    // Camera setup
    this.camera = new THREE.PerspectiveCamera(
      60,
      container.clientWidth / container.clientHeight,
      0.1,
      10000
    );
    this.camera.position.set(0, 50, 50);
    this.camera.lookAt(0, 0, 0);

    // Renderer setup
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setSize(container.clientWidth, container.clientHeight);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    container.appendChild(this.renderer.domElement);

    // Controls
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.05;
    this.controls.maxPolarAngle = Math.PI * 0.9;
    this.controls.minDistance = 5;
    this.controls.maxDistance = 500;

    // Lighting
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.6);
    this.scene.add(ambientLight);

    const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
    directionalLight.position.set(50, 100, 50);
    this.scene.add(directionalLight);

    // Ground plane
    const groundGeometry = new THREE.PlaneGeometry(1000, 1000);
    const groundMaterial = new THREE.MeshStandardMaterial({
      color: 0x2d2d44,
      roughness: 0.8,
    });
    this.ground = new THREE.Mesh(groundGeometry, groundMaterial);
    this.ground.rotation.x = -Math.PI / 2;
    this.ground.position.y = -0.1;
    this.scene.add(this.ground);

    // Grid helper
    this.gridHelper = new THREE.GridHelper(1000, 100, 0x444466, 0x333355);
    this.scene.add(this.gridHelper);

    // Handle resize
    window.addEventListener('resize', this.onResize.bind(this));

    // Start render loop
    this.animate();
  }

  private onResize(): void {
    const width = this.container.clientWidth;
    const height = this.container.clientHeight;

    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(width, height);
  }

  private animate(): void {
    requestAnimationFrame(this.animate.bind(this));
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }

  updatePlayers(players: Map<number, PlayerState>): void {
    // Track which players are still active
    const activeIds = new Set<number>();

    for (const [id, state] of players) {
      activeIds.add(id);

      let mesh = this.playerMeshes.get(id);
      if (!mesh) {
        mesh = this.createPlayerMesh(state);
        this.playerMeshes.set(id, mesh);
        this.scene.add(mesh.group);
      }

      // Update position (convert from CS coordinates)
      // CS uses: X = forward, Y = left, Z = up
      // Three.js uses: X = right, Y = up, Z = forward
      const x = state.origin[0] * this.SCALE;
      const y = state.origin[2] * this.SCALE; // Z in CS is Y in Three.js
      const z = -state.origin[1] * this.SCALE; // Y in CS is -Z in Three.js

      mesh.group.position.set(x, y, z);

      // Update rotation (yaw only for simplicity)
      // CS angles: [pitch, yaw, roll]
      const yaw = THREE.MathUtils.degToRad(-state.angles[1] + 90);
      mesh.group.rotation.y = yaw;

      // Update color based on team and alive status
      const material = mesh.body.material as THREE.MeshStandardMaterial;
      if (!state.alive) {
        material.color.setHex(0x555555);
        material.opacity = 0.5;
      } else {
        material.opacity = 1.0;
        switch (state.team) {
          case 'CT':
            material.color.setHex(0x4fc3f7);
            break;
          case 'T':
            material.color.setHex(0xffd54f);
            break;
          default:
            material.color.setHex(0x81c784);
        }
      }

      // Update label only if name changed
      if (mesh.labelText !== state.name) {
        this.updateLabel(mesh.label, state.name);
        mesh.labelText = state.name;
      }
    }

    // Remove meshes for players no longer in the state
    for (const [id, mesh] of this.playerMeshes) {
      if (!activeIds.has(id)) {
        this.scene.remove(mesh.group);
        this.playerMeshes.delete(id);
      }
    }
  }

  private createPlayerMesh(state: PlayerState): PlayerMesh {
    const group = new THREE.Group();

    // Body - cylinder
    const bodyGeometry = new THREE.CylinderGeometry(
      this.PLAYER_RADIUS,
      this.PLAYER_RADIUS,
      this.PLAYER_HEIGHT,
      16
    );
    const bodyMaterial = new THREE.MeshStandardMaterial({
      color: 0x81c784,
      transparent: true,
      opacity: 1.0,
    });
    const body = new THREE.Mesh(bodyGeometry, bodyMaterial);
    body.position.y = this.PLAYER_HEIGHT / 2;
    group.add(body);

    // Name label
    const label = this.createLabel(state.name);
    label.position.y = this.PLAYER_HEIGHT + 0.5;
    group.add(label);

    return { group, body, label, labelText: state.name };
  }

  private createLabel(text: string): THREE.Sprite {
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d')!;
    canvas.width = 256;
    canvas.height = 64;

    ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.font = 'bold 24px Arial';
    ctx.fillStyle = '#ffffff';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, canvas.width / 2, canvas.height / 2);

    const texture = new THREE.CanvasTexture(canvas);
    const material = new THREE.SpriteMaterial({ map: texture });
    const sprite = new THREE.Sprite(material);
    sprite.scale.set(4, 1, 1);

    return sprite;
  }

  private updateLabel(label: THREE.Sprite, text: string): void {
    const material = label.material as THREE.SpriteMaterial;
    const texture = material.map;
    if (!texture) return;

    const canvas = texture.image as HTMLCanvasElement;
    const ctx = canvas.getContext('2d')!;

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.font = 'bold 24px Arial';
    ctx.fillStyle = '#ffffff';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, canvas.width / 2, canvas.height / 2);

    texture.needsUpdate = true;
  }

  focusOnPlayer(state: PlayerState): void {
    const x = state.origin[0] * this.SCALE;
    const y = state.origin[2] * this.SCALE;
    const z = -state.origin[1] * this.SCALE;

    this.controls.target.set(x, y, z);
    this.camera.position.set(x + 20, y + 30, z + 20);
  }

  focusOnOrigin(): void {
    this.controls.target.set(0, 0, 0);
    this.camera.position.set(0, 50, 50);
  }

  loadMap(bsp: ParsedBSP): void {
    // Remove old map if exists
    if (this.mapGroup) {
      this.scene.remove(this.mapGroup);
      this.mapGroup = null;
    }

    // Hide default ground and grid when we have a real map
    this.ground.visible = false;
    this.gridHelper.visible = false;

    // Create BSP renderer and generate mesh
    const bspRenderer = new BSPRenderer(bsp);
    this.mapGroup = bspRenderer.createMesh();
    this.scene.add(this.mapGroup);

    // Adjust camera to map bounds
    const bounds = bspRenderer.getBounds();
    const center = new THREE.Vector3();
    center.addVectors(bounds.min, bounds.max).multiplyScalar(0.5);

    const size = new THREE.Vector3();
    size.subVectors(bounds.max, bounds.min);
    const maxDim = Math.max(size.x, size.y, size.z);

    this.controls.target.copy(center);
    this.camera.position.set(
      center.x + maxDim * 0.5,
      center.y + maxDim * 0.5,
      center.z + maxDim * 0.5
    );

    // Update controls distance limits based on map size
    this.controls.minDistance = maxDim * 0.1;
    this.controls.maxDistance = maxDim * 3;

    // Try to position at a spawn point
    const spawns = bspRenderer.getSpawnPoints();
    if (spawns.length > 0) {
      const spawn = spawns[0];
      this.controls.target.set(spawn.x, spawn.y, spawn.z);
      this.camera.position.set(spawn.x + 10, spawn.y + 15, spawn.z + 10);
    }

    console.log(`Map loaded: ${bsp.faces.length} faces, ${bsp.vertices.length} vertices`);
  }

  clearMap(): void {
    if (this.mapGroup) {
      this.scene.remove(this.mapGroup);
      this.mapGroup = null;
    }
    this.ground.visible = true;
    this.gridHelper.visible = true;
  }
}
