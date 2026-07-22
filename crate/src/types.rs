use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Vec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl Vec3 {
    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }

    pub fn zero() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            z: 0.0,
        }
    }
}

// Demo types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DemoHeader {
    pub magic: String,
    pub demo_protocol: i32,
    pub network_protocol: i32,
    pub map_name: String,
    pub game_dir: String,
    pub directory_offset: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirectoryEntry {
    pub entry_type: i32,
    pub description: String,
    pub flags: i32,
    pub cd_track: i32,
    pub track_time: f32,
    pub frame_count: i32,
    pub offset: i32,
    pub file_length: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum FrameType {
    /// NetMsg frame type 0: startup/info messages (no network data)
    NetMsgStart = 0,
    /// NetMsg frame type 1: network messages with entity data
    NetMsg = 1,
    DemoStart = 2,
    ConsoleCommand = 3,
    ClientData = 4,
    NextSection = 5,
    Event = 6,
    WeaponAnim = 7,
    Sound = 8,
    DemoBuffer = 9,
    Unknown = 255,
}

impl From<i32> for FrameType {
    fn from(v: i32) -> Self {
        // GoldSrc demo frame types for Protocol 47:
        // 0 = NetMsg (startup, msglen=0)
        // 1 = NetMsg (game data with actual network messages)
        // 2 = DemoStart
        // 3 = ConsoleCommand
        // 4 = ClientData
        // 5 = NextSection
        // 6 = Event
        // 7 = WeaponAnim
        // 8 = Sound
        // 9 = DemoBuffer
        match v {
            0 => FrameType::NetMsgStart,
            1 => FrameType::NetMsg,
            2 => FrameType::DemoStart,
            3 => FrameType::ConsoleCommand,
            4 => FrameType::ClientData,
            5 => FrameType::NextSection,
            6 => FrameType::Event,
            7 => FrameType::WeaponAnim,
            8 => FrameType::Sound,
            9 => FrameType::DemoBuffer,
            _ => FrameType::Unknown,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientData {
    pub origin: Vec3,
    pub viewangles: Vec3,
    pub weapon_bits: i32,
    pub fov: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DemoFrame {
    pub frame_type: FrameType,
    pub time: f32,
    pub frame: i32,
    pub client_data: Option<ClientData>,
    pub command: Option<String>,
    /// Recorder-local first-person weapon sequence/body from DEM_WEAPONANIM.
    pub weapon_anim: Option<(i32, i32)>,
    pub sound: Option<DemoSound>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerInfo {
    pub index: u8,
    pub name: String,
    pub team: String,
    pub model: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParsedDemo {
    pub header: DemoHeader,
    pub directory: Vec<DirectoryEntry>,
    pub frames: Vec<DemoFrame>,
    pub players: Vec<PlayerInfo>,
    /// DemoBuffer frames containing network data (time, data)
    #[serde(skip)]
    pub demo_buffers: Vec<(f32, Vec<u8>)>,
    /// (file offset, frame time) anchors for byte-position event scans
    #[serde(skip)]
    pub buffer_anchors: Vec<(u64, f32)>,
}

// Timeline types for efficient playback
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerState {
    pub origin: Vec3,
    pub angles: Vec3,
    #[serde(default)]
    pub velocity: Vec3,
    pub name: String,
    #[serde(default)]
    pub gait: u8,
    #[serde(default)]
    pub sequence: u8,
    #[serde(default)]
    pub frame: u8,
    #[serde(default)]
    pub effects: u32,
    #[serde(default)]
    pub ducking: bool,
    #[serde(default)]
    pub weapon: u16,
    /// Entity health is available in some HLTV streams. -1 means the demo
    /// did not expose it, which is distinct from a dead player at 0 HP.
    #[serde(default = "unknown_health")]
    pub health: i16,
}

fn unknown_health() -> i16 {
    -1
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineEntry {
    pub time: f32,
    pub players: Vec<PlayerState>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Timeline {
    pub entries: Vec<TimelineEntry>,
    pub duration: f32,
    pub events: Vec<GameEvent>,
    /// Roster rebuilt from wire SVC_UpdateUserInfo (slot-accurate), joined
    /// with scanned userinfo for team/model. Empty if no wire data was seen.
    #[serde(default)]
    pub wire_players: Vec<PlayerInfo>,
    /// Full-rate recorder camera track from ClientData frames (POV demos).
    /// Much higher rate than the sampled entries; used for smooth first-person.
    #[serde(default)]
    pub pov_track: Vec<PovSample>,
    /// Non-player object samples (grenades in flight, planted C4, ...)
    #[serde(default)]
    pub obj_track: Vec<ObjSample>,
    /// modelindex -> precache name (from SVC_RESOURCELIST)
    #[serde(default)]
    pub model_names: Vec<(u16, String)>,
    /// Weapon-fire events: (time, 0-based shooter slot)
    #[serde(default)]
    pub shot_track: Vec<(f32, u8)>,
    /// Recorder-local HUD messages. These are authoritative for the POV
    /// camera only; they must not be attributed to arbitrary HLTV players.
    #[serde(default)]
    pub hud_track: Vec<HudUpdate>,
    /// WeaponList definitions used to join CurWeapon with AmmoX.
    #[serde(default)]
    pub hud_weapons: Vec<HudWeaponDef>,
    /// Recorded spectator target/mode changes from SetView and director data.
    #[serde(default)]
    pub observer_track: Vec<ObserverSample>,
    /// Recorder-local first-person weapon animation changes.
    #[serde(default)]
    pub weapon_anim_track: Vec<WeaponAnimSample>,
    /// Recorder-local DEM_SOUND commands, preserving the captured sample mix.
    #[serde(default)]
    pub sound_track: Vec<DemoSound>,
    /// Positional SVC_SOUND messages from the server.
    #[serde(default)]
    pub network_sound_track: Vec<NetworkSound>,
    /// Recorded SVC_TEMPENTITY effects such as smoke, impacts, and tracers.
    #[serde(default)]
    pub temp_effect_track: Vec<TempEffect>,
    /// Authoritative per-player scoreboard/team/attribute updates.
    #[serde(default)]
    pub player_stats_track: Vec<PlayerStatsUpdate>,
}

/// A sampled non-player object (grenade, planted C4, ...) on the timeline
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjSample {
    pub time: f32,
    pub ent: u16,
    /// 1=hegrenade 2=flashbang 3=smokegrenade 4=c4
    pub kind: u8,
    pub origin: Vec3,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PovSample {
    pub time: f32,
    pub origin: Vec3,
    pub angles: Vec3,
    /// GoldSrc clientdata weapon ownership bitmask (bit = weapon id).
    #[serde(default)]
    pub weapon_bits: i32,
}

/// Compact recorder HUD update kinds:
/// 1=health 2=armor 3=money 4=active weapon/clip 5=ammo
/// 6=hide flags 7=FOV 8=reset 9=screen fade 10=screen fade flags
/// 11=timed action bar (duration seconds, starting percent).
/// Screen fade packs the raw 16-bit duration/hold values into `a` and RGBA
/// bytes into `b`; GoldSrc uses a 4096-unit fixed-point second.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HudUpdate {
    pub time: f32,
    pub kind: u8,
    pub a: i32,
    pub b: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HudWeaponDef {
    pub id: u8,
    pub ammo_id: i8,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObserverSample {
    pub time: f32,
    /// GoldSrc entity index (1-based); 0 means world/free camera.
    pub target: u16,
    /// GoldSrc observer/director mode when known; 0 means unspecified.
    pub mode: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WeaponAnimSample {
    pub time: f32,
    pub sequence: u8,
    pub body: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DemoSound {
    pub time: f32,
    pub sample: String,
    pub volume: f32,
    pub attenuation: f32,
    pub pitch: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkSound {
    pub time: f32,
    pub sample: String,
    pub origin: Vec3,
    pub volume: f32,
    pub attenuation: f32,
    pub pitch: u8,
    pub entity: u16,
    pub channel: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TempEffect {
    pub time: f32,
    pub kind: u8,
    pub origin: Vec3,
    pub end: Vec3,
    pub color: u32,
    pub scale: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerStatsUpdate {
    pub time: f32,
    /// Zero-based client slot.
    pub slot: u8,
    pub frags: Option<i16>,
    pub deaths: Option<i16>,
    pub team: Option<String>,
    /// ScoreAttrib flags: bit 0 dead, bit 1 bomb, bit 2 VIP.
    pub flags: Option<u8>,
}

// Game events (kills, rounds, etc.)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GameEventType {
    Kill,             // Player killed another player
    Suicide,          // Player killed themselves
    TeamKill,         // Player killed teammate
    RoundStart,       // New round started
    RoundEnd,         // Round ended
    TeamScore,        // Team score update
    RoundTime,        // Round time update (seconds remaining)
    BombPlanted,      // Bomb was planted
    BombDefused,      // Bomb was defused
    BombExploded,     // Bomb exploded
    PlayerJoin,       // Player joined
    PlayerDisconnect, // Player disconnected
    TextMessage,      // Chat or game message
    ModelChange,      // Player model changed (side switch at halftime)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameEvent {
    pub time: f32,
    pub event_type: GameEventType,
    pub data: GameEventData,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameEventData {
    // For kills
    pub killer: Option<String>,
    pub victim: Option<String>,
    pub weapon: Option<String>,
    pub headshot: bool,
    // For text messages
    pub message: Option<String>,
    // For round events
    pub winner: Option<String>, // "CT" or "T"
    // For team score updates
    pub team: Option<String>,
    pub score: Option<i32>,
    // For round timer updates
    pub round_time: Option<i32>,
    // For model/team changes
    #[serde(default)]
    pub player: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
}

// BSP types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BspVertex {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BspFace {
    pub vertices: Vec<BspVertex>,
    pub normal: Vec3,
    pub texture_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BspEntity {
    pub classname: String,
    pub origin: Option<Vec3>,
    pub properties: Vec<(String, String)>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParsedBsp {
    pub vertices: Vec<f32>, // Flattened [x,y,z, x,y,z, ...]
    pub normals: Vec<f32>,  // Flattened [nx,ny,nz, ...]
    pub colors: Vec<f32>,   // Flattened [r,g,b, ...]
    pub entities: Vec<BspEntity>,
    pub bounds_min: Vec3,
    pub bounds_max: Vec3,
}
