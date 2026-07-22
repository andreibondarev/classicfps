/// GoldSrc SVC (Server to Client) message parser
///
/// DemoBuffer frames contain raw network data that was sent from server to client.
/// This module parses the SVC messages to extract entity positions and other game state.
///
/// Wire formats follow the GoldSrc protocol (protocol 46-48) as implemented by the
/// engine and cross-checked against coldemoplayer's HalfLifeDemoParser. Key points:
/// - Delta-compressed structures (entities, client data, events, delta descriptions)
///   are encoded as: 3-bit bitmask byte count, N mask bytes, then present fields in
///   field order. Field decoding depends on DT_* flags from the definition.
/// - Definitions arrive via SVC_DELTADESCRIPTION, themselves delta-encoded against
///   the hardcoded delta_description_t meta-definition.
/// - Bit-level messages are padded to a byte boundary at the end of the message.
use crate::bitreader::BitReader;
use crate::delta::{
    meta_delta_description, DeltaDefinition, DeltaFieldDef, DeltaFlags, DeltaRegistry, EntityDelta,
};
use crate::entity::{Entity, EntityState};
use crate::events::EventParser;
use crate::types::{NetworkSound, TempEffect, Vec3};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

/// SVC message types
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SvcMessage {
    Bad = 0,
    Nop = 1,
    Disconnect = 2,
    Event = 3,
    Version = 4,
    SetView = 5,
    Sound = 6,
    Time = 7,
    Print = 8,
    StuffText = 9,
    SetAngle = 10,
    ServerInfo = 11,
    LightStyle = 12,
    UpdateUserInfo = 13,
    DeltaDescription = 14,
    ClientData = 15,
    StopSound = 16,
    Pings = 17,
    Particle = 18,
    Damage = 19,
    SpawnStatic = 20,
    EventReliable = 21,
    SpawnBaseline = 22,
    TempEntity = 23,
    SetPause = 24,
    SignonNum = 25,
    CenterPrint = 26,
    KilledMonster = 27,
    FoundSecret = 28,
    SpawnStaticSound = 29,
    Intermission = 30,
    Finale = 31,
    CdTrack = 32,
    Restore = 33,
    CutScene = 34,
    WeaponAnim = 35,
    DecalName = 36,
    RoomType = 37,
    AddAngle = 38,
    NewUserMsg = 39,
    PacketEntities = 40,
    DeltaPacketEntities = 41,
    Choke = 42,
    ResourceList = 43,
    NewMoveVars = 44,
    ResourceRequest = 45,
    Customization = 46,
    CrosshairAngle = 47,
    SoundFade = 48,
    FileTxferFailed = 49,
    Hltv = 50,
    Director = 51,
    VoiceInit = 52,
    VoiceData = 53,
    SendExtraInfo = 54,
    TimeScale = 55,
    ResourceLocation = 56,
    SendCvarValue = 57,
    SendCvarValue2 = 58,
}

impl From<u8> for SvcMessage {
    fn from(v: u8) -> Self {
        match v {
            0 => SvcMessage::Bad,
            1 => SvcMessage::Nop,
            2 => SvcMessage::Disconnect,
            3 => SvcMessage::Event,
            4 => SvcMessage::Version,
            5 => SvcMessage::SetView,
            6 => SvcMessage::Sound,
            7 => SvcMessage::Time,
            8 => SvcMessage::Print,
            9 => SvcMessage::StuffText,
            10 => SvcMessage::SetAngle,
            11 => SvcMessage::ServerInfo,
            12 => SvcMessage::LightStyle,
            13 => SvcMessage::UpdateUserInfo,
            14 => SvcMessage::DeltaDescription,
            15 => SvcMessage::ClientData,
            16 => SvcMessage::StopSound,
            17 => SvcMessage::Pings,
            18 => SvcMessage::Particle,
            19 => SvcMessage::Damage,
            20 => SvcMessage::SpawnStatic,
            21 => SvcMessage::EventReliable,
            22 => SvcMessage::SpawnBaseline,
            23 => SvcMessage::TempEntity,
            24 => SvcMessage::SetPause,
            25 => SvcMessage::SignonNum,
            26 => SvcMessage::CenterPrint,
            27 => SvcMessage::KilledMonster,
            28 => SvcMessage::FoundSecret,
            29 => SvcMessage::SpawnStaticSound,
            30 => SvcMessage::Intermission,
            31 => SvcMessage::Finale,
            32 => SvcMessage::CdTrack,
            33 => SvcMessage::Restore,
            34 => SvcMessage::CutScene,
            35 => SvcMessage::WeaponAnim,
            36 => SvcMessage::DecalName,
            37 => SvcMessage::RoomType,
            38 => SvcMessage::AddAngle,
            39 => SvcMessage::NewUserMsg,
            40 => SvcMessage::PacketEntities,
            41 => SvcMessage::DeltaPacketEntities,
            42 => SvcMessage::Choke,
            43 => SvcMessage::ResourceList,
            44 => SvcMessage::NewMoveVars,
            45 => SvcMessage::ResourceRequest,
            46 => SvcMessage::Customization,
            47 => SvcMessage::CrosshairAngle,
            48 => SvcMessage::SoundFade,
            49 => SvcMessage::FileTxferFailed,
            50 => SvcMessage::Hltv,
            51 => SvcMessage::Director,
            52 => SvcMessage::VoiceInit,
            53 => SvcMessage::VoiceData,
            54 => SvcMessage::SendExtraInfo,
            55 => SvcMessage::TimeScale,
            56 => SvcMessage::ResourceLocation,
            57 => SvcMessage::SendCvarValue,
            58 => SvcMessage::SendCvarValue2,
            _ => SvcMessage::Bad,
        }
    }
}

// === Parser session state (per demo) ===

thread_local! {
    static DELTA_REGISTRY: RefCell<DeltaRegistry> = RefCell::new(DeltaRegistry::new());
    static MODEL_NAMES: RefCell<std::collections::HashMap<u16, String>> = RefCell::new(Default::default());
    static SOUND_NAMES: RefCell<std::collections::HashMap<u16, String>> = RefCell::new(Default::default());
    static EVENT_NAMES: RefCell<std::collections::HashMap<u16, String>> = RefCell::new(Default::default());
    static EVENT_STATS: Cell<(u32, u32)> = Cell::new((0, 0)); // (svc_event msgs, events w/ entindex)
    static LAST_PACKET_ORDER: RefCell<Vec<u16>> = RefCell::new(Vec::new());
    static MAX_CLIENTS: Cell<u16> = Cell::new(32);
    static IS_HLTV: Cell<bool> = Cell::new(false);
    static DESYNC_LOGS: Cell<u32> = Cell::new(0);
}

/// Reset all per-demo parser state. Call before parsing a new demo.
pub fn reset_parser_state() {
    DELTA_REGISTRY.with(|reg| reg.borrow_mut().clear());
    MODEL_NAMES.with(|m| m.borrow_mut().clear());
    SOUND_NAMES.with(|m| m.borrow_mut().clear());
    EVENT_NAMES.with(|m| m.borrow_mut().clear());
    MAX_CLIENTS.with(|c| c.set(32));
    IS_HLTV.with(|c| c.set(false));
    DESYNC_LOGS.with(|c| c.set(0));
}

fn get_def(name: &str) -> Result<Rc<DeltaDefinition>, String> {
    DELTA_REGISTRY
        .with(|reg| reg.borrow().get(name))
        .ok_or_else(|| format!("missing delta definition '{}'", name))
}

fn max_clients() -> u16 {
    MAX_CLIENTS.with(|c| c.get())
}

/// Model precache name for an entity modelindex (from SVC_RESOURCELIST)
pub fn model_name(index: u16) -> Option<String> {
    MODEL_NAMES.with(|m| m.borrow().get(&index).cloned())
}

fn sound_name(index: u16) -> Option<String> {
    SOUND_NAMES.with(|m| m.borrow().get(&index).cloned())
}

/// Debug: (svc_event message count, events with entindex), event-script table size
pub fn debug_event_stats() -> (u32, u32, usize) {
    let (a, b) = EVENT_STATS.with(|c| c.get());
    (a, b, EVENT_NAMES.with(|m| m.borrow().len()))
}

/// Snapshot of the whole modelindex->name table
pub fn all_model_names() -> Vec<(u16, String)> {
    MODEL_NAMES.with(|m| m.borrow().iter().map(|(k, v)| (*k, v.clone())).collect())
}

// === Generic delta decoding ===

enum DeltaVal {
    Num(f64),
    Str(String),
}

/// Read one delta-compressed structure: 3-bit mask byte count, mask bytes,
/// then each flagged field in definition order.
fn read_delta(
    reader: &mut BitReader,
    def: &DeltaDefinition,
    mut visit: impl FnMut(&DeltaFieldDef, DeltaVal),
) -> Result<(), String> {
    let n_bytes = reader.read_bits(3) as usize;
    if n_bytes == 0 {
        return Ok(());
    }
    if reader.bits_remaining() < n_bytes * 8 {
        return Err("delta bitmask overflows buffer".to_string());
    }

    let mut mask = [0u8; 7];
    for slot in mask.iter_mut().take(n_bytes) {
        *slot = reader.read_u8();
    }

    for i in 0..n_bytes {
        for j in 0..8 {
            let index = i * 8 + j;
            if index >= def.fields.len() {
                return Ok(());
            }
            if mask[i] & (1 << j) != 0 {
                let field = &def.fields[index];
                let value = read_delta_value(reader, field)?;
                visit(field, value);
            }
        }
    }

    Ok(())
}

/// Decode a single delta field value according to its DT_* flags.
fn read_delta_value(reader: &mut BitReader, field: &DeltaFieldDef) -> Result<DeltaVal, String> {
    let flags = field.flags;

    if flags.contains(DeltaFlags::STRING) {
        return Ok(DeltaVal::Str(reader.read_string()));
    }

    let bits = field.bits as usize;
    if bits == 0 || bits > 32 {
        return Err(format!(
            "field '{}' has invalid bit count {}",
            field.name, bits
        ));
    }
    if reader.bits_remaining() < bits {
        return Err(format!("field '{}' overflows buffer", field.name));
    }

    let signed = flags.contains(DeltaFlags::SIGNED);
    let divisor = if field.divisor.is_finite() && field.divisor != 0.0 {
        field.divisor
    } else {
        1.0
    };

    if flags.intersects(DeltaFlags::BYTE | DeltaFlags::SHORT | DeltaFlags::INTEGER) {
        let value = if signed {
            let negative = reader.read_bit();
            let magnitude = reader.read_bits(bits - 1) as i64;
            let div = divisor as i64;
            let v = if div > 1 { magnitude / div } else { magnitude };
            if negative {
                -v
            } else {
                v
            }
        } else {
            let magnitude = reader.read_bits(bits) as i64;
            let div = divisor as i64;
            if div > 1 {
                magnitude / div
            } else {
                magnitude
            }
        };
        return Ok(DeltaVal::Num(value as f64));
    }

    if flags.intersects(DeltaFlags::FLOAT | DeltaFlags::TIMEWINDOW_8 | DeltaFlags::TIMEWINDOW_BIG) {
        let (negative, magnitude_bits) = if signed {
            (reader.read_bit(), bits - 1)
        } else {
            (false, bits)
        };
        let magnitude = if magnitude_bits > 0 {
            reader.read_bits(magnitude_bits) as f64
        } else {
            0.0
        };
        let value = magnitude / divisor as f64;
        return Ok(DeltaVal::Num(if negative { -value } else { value }));
    }

    if flags.contains(DeltaFlags::ANGLE) {
        let raw = reader.read_bits(bits);
        return Ok(DeltaVal::Num(raw as f64 * (360.0 / (1u64 << bits) as f64)));
    }

    // Unknown field type: consume the bits raw to stay aligned
    Ok(DeltaVal::Num(reader.read_bits(bits) as f64))
}

/// Read a delta-compressed structure, discarding all values.
fn skip_delta(reader: &mut BitReader, def: &DeltaDefinition) -> Result<(), String> {
    read_delta(reader, def, |_, _| {})
}

/// Read an entity delta, capturing position-relevant fields.
fn read_entity_delta(reader: &mut BitReader, def: &DeltaDefinition) -> Result<EntityDelta, String> {
    let mut delta = EntityDelta::new();
    read_delta(reader, def, |field, value| {
        if let DeltaVal::Num(v) = value {
            match field.name.as_str() {
                "origin[0]" => delta.origin[0] = Some(v as f32),
                "origin[1]" => delta.origin[1] = Some(v as f32),
                "origin[2]" => delta.origin[2] = Some(v as f32),
                "angles[0]" => delta.angles[0] = Some(v as f32),
                "angles[1]" => delta.angles[1] = Some(v as f32),
                "angles[2]" => delta.angles[2] = Some(v as f32),
                "velocity[0]" => delta.velocity[0] = Some(v as f32),
                "velocity[1]" => delta.velocity[1] = Some(v as f32),
                "velocity[2]" => delta.velocity[2] = Some(v as f32),
                "modelindex" => delta.modelindex = Some(v as u16),
                "sequence" => delta.sequence = Some(v as u8),
                "gaitsequence" => delta.gaitsequence = Some(v as u8),
                "weaponmodel" => delta.weaponmodel = Some(v as u16),
                "frame" => delta.frame = Some(v as u8),
                "effects" => delta.effects = Some(v as u8),
                "solid" => delta.solid = Some(v as u8),
                "health" => delta.health = Some(v as i16),
                "usehull" => delta.usehull = Some(v as u8),
                _ => {}
            }
        }
    })?;
    Ok(delta)
}

/// Definition name for an entity in SVC_PACKETENTITIES / SVC_DELTAPACKETENTITIES.
fn packet_entity_def_name(index: u16, custom: bool) -> &'static str {
    if index >= 1 && index <= max_clients() {
        "entity_state_player_t"
    } else if custom {
        "custom_entity_state_t"
    } else {
        "entity_state_t"
    }
}

/// Parse a DemoBuffer's network data with event parsing support
pub fn parse_demo_buffer_with_events(
    data: &[u8],
    state: &mut EntityState,
    event_parser: &mut EventParser,
    debug: bool,
) -> Result<(), String> {
    if data.len() < 4 {
        return Ok(());
    }

    if debug {
        let preview: Vec<String> = data.iter().take(64).map(|b| format!("{:02x}", b)).collect();
        crate::console_log!("  Buffer first 64 bytes: {}", preview.join(" "));
    }

    // Strategy 1: Parse the SVC stream sequentially from the start.
    // If it parses cleanly to the end of the buffer, we're done.
    let first_byte = data[0];
    if first_byte <= 58 {
        if debug {
            crate::console_log!(
                "  Parsing SVC stream from offset 0, first byte: {} ({:?})",
                first_byte,
                SvcMessage::from(first_byte)
            );
        }
        let mut reader = BitReader::new(data);
        if let Ok(true) = try_parse_svc_stream_with_events(&mut reader, state, event_parser, debug)
        {
            return Ok(());
        }
    }

    // Fallback strategies for buffers that don't parse cleanly:
    // scan for recognizable entity messages directly.

    // Strategy 2: Directly find and parse SpawnBaseline messages
    let mut baselines_found = 0;
    for i in 0..data.len().saturating_sub(20) {
        if data[i] == 22 {
            // SVC_SPAWNBASELINE
            let b0 = data.get(i + 1).copied().unwrap_or(0);
            let b1 = data.get(i + 2).copied().unwrap_or(0);
            let index = (b0 as u16) | (((b1 & 0x07) as u16) << 8);

            if index < 500 {
                let mut reader = BitReader::new(&data[i..]);
                reader.skip_bits(8);
                if let Ok(count) = parse_spawn_baseline(&mut reader, state) {
                    baselines_found += count;
                }
            }
        }
    }

    if debug && baselines_found > 0 {
        crate::console_log!("  Parsed {} baseline entities (scan)", baselines_found);
    }

    // Strategy 3: Directly find and parse PacketEntities/DeltaPacketEntities messages
    let mut packet_updates = 0;
    for i in 0..data.len().saturating_sub(10) {
        let byte = data[i];
        if byte == 40 || byte == 41 {
            let num_entities = u16::from_le_bytes([
                data.get(i + 1).copied().unwrap_or(0),
                data.get(i + 2).copied().unwrap_or(0),
            ]);

            if num_entities > 0 && num_entities <= 256 {
                let is_delta = byte == 41;
                let mut reader = BitReader::new(&data[i..]);
                reader.skip_bits(8);
                if let Ok(count) =
                    parse_packet_entities(&mut reader, state, is_delta, debug && packet_updates < 5)
                {
                    packet_updates += count;
                }
            }
        }
    }

    if debug && packet_updates > 0 {
        crate::console_log!(
            "  Direct scan found {} entity updates total",
            packet_updates
        );
    }

    Ok(())
}

/// Scan buffer for user message definitions by looking for known message names
pub fn scan_for_user_message_defs(data: &[u8], event_parser: &mut EventParser) {
    // Known CS 1.6 user message names (16 bytes, null-padded)
    let known_names = [
        "DeathMsg",
        "TextMsg",
        "SendAudio",
        "ResetHUD",
        "RoundTime",
        "ScoreInfo",
        "ScoreAttrib",
        "TeamScore",
        "TeamInfo",
        "SayText",
        "GameTitle",
        "Health",
        "Battery",
        "Money",
        "CurWeapon",
        "AmmoX",
        "HideWeapon",
        "SetFOV",
        "ScreenFade",
        "BarTime",
        "BarTime2",
        "WeaponList",
        "StatusIcon",
    ];

    for name in &known_names {
        let name_bytes = name.as_bytes();
        for i in 0..data.len().saturating_sub(19) {
            if data[i..].starts_with(name_bytes) {
                // Check if followed by nulls (name is null-padded to 16 bytes)
                let padding_start = i + name_bytes.len();
                if padding_start < data.len() && data[padding_start] == 0 {
                    // Found a name - check if preceded by SVC_NEWUSERMSG (39) + id + size
                    // Format: 39 <msg_id:1> <size:1> <name:16>
                    if i >= 3 && data[i - 3] == 39 {
                        let msg_id = data[i - 2];
                        let size = data[i - 1] as i8;
                        if msg_id >= 64 {
                            event_parser.register_user_message(msg_id, name.to_string(), size);
                        }
                    }
                }
            }
        }
    }
}

/// Scan raw data for kill events (DeathMsg format)
/// DeathMsg format: <killer_id:1> <victim_id:1> <headshot:1> <weapon_name:string>
pub fn scan_for_death_messages(data: &[u8], event_parser: &mut EventParser) {
    // Common CS weapons
    let weapons = [
        "ak47",
        "m4a1",
        "awp",
        "deagle",
        "usp",
        "glock18",
        "glock",
        "famas",
        "galil",
        "scout",
        "sg552",
        "aug",
        "mp5navy",
        "p90",
        "mac10",
        "tmp",
        "ump45",
        "knife",
        "hegrenade",
        "c4",
        "sg550",
        "g3sg1",
        "m249",
        "p228",
        "elite",
        "fiveseven",
        "m3",
        "xm1014",
        "p90",
    ];

    for weapon in &weapons {
        let weapon_bytes = weapon.as_bytes();
        for i in 3..data.len().saturating_sub(weapon_bytes.len() + 1) {
            // Check if this looks like a weapon name followed by null
            if data[i..].starts_with(weapon_bytes) {
                let after_weapon = i + weapon_bytes.len();
                if after_weapon < data.len() && data[after_weapon] == 0 {
                    // Check preceding bytes for valid player IDs
                    let killer_id = data[i - 3];
                    let victim_id = data[i - 2];
                    let headshot = data[i - 1];

                    // Valid player IDs are 0-32, headshot is 0 or 1
                    if killer_id <= 32 && victim_id <= 32 && victim_id > 0 && headshot <= 1 {
                        // Check if this event already exists (avoid duplicates)
                        let time = event_parser.current_time;
                        let killer_name = event_parser.get_player_name(killer_id);
                        let victim_name = event_parser.get_player_name(victim_id);

                        // Check for duplicate (same victim, similar time)
                        let is_duplicate = event_parser.events.iter().any(|e| {
                            (e.time - time).abs() < 0.5
                                && e.data.victim == victim_name
                                && matches!(
                                    e.event_type,
                                    crate::types::GameEventType::Kill
                                        | crate::types::GameEventType::Suicide
                                )
                        });

                        if !is_duplicate {
                            use crate::types::{GameEvent, GameEventData, GameEventType};

                            let event_type = if killer_id == victim_id || killer_id == 0 {
                                GameEventType::Suicide
                            } else {
                                GameEventType::Kill
                            };

                            event_parser.events.push(GameEvent {
                                time,
                                event_type,
                                data: GameEventData {
                                    player: None,
                                    model: None,
                                    killer: killer_name,
                                    victim: victim_name,
                                    weapon: Some(weapon.to_string()),
                                    headshot: headshot != 0,
                                    message: None,
                                    winner: None,
                                    team: None,
                                    score: None,
                                    round_time: None,
                                },
                            });
                        }
                    }
                }
            }
        }
    }
}

/// Parse SVC messages sequentially. Returns Ok(true) if the stream parsed
/// cleanly to the end of the buffer, Ok(false) if it desynced partway.
fn try_parse_svc_stream_with_events(
    reader: &mut BitReader,
    state: &mut EntityState,
    event_parser: &mut EventParser,
    debug: bool,
) -> Result<bool, String> {
    let mut msg_count = 0;
    let mut clean = true;
    let mut history: Vec<u8> = Vec::new();

    while reader.bits_remaining() >= 8 {
        let msg_type_raw = reader.read_u8();
        history.push(msg_type_raw);

        if debug && msg_count < 20 {
            crate::console_log!(
                "  SVC[{}]: {:?} ({}), remaining={}",
                msg_count,
                SvcMessage::from(msg_type_raw),
                msg_type_raw,
                reader.bits_remaining()
            );
        }

        // User messages (ID >= 64) are registered via SVC_NEWUSERMSG
        if msg_type_raw >= 64 {
            match parse_user_message(reader, event_parser, msg_type_raw) {
                Ok(()) => {
                    msg_count += 1;
                    continue;
                }
                Err(e) => {
                    if debug {
                        crate::console_log!("  User msg {} failed: {}", msg_type_raw, e);
                    }
                    clean = false;
                    break;
                }
            }
        }

        let result: Result<(), String> = match SvcMessage::from(msg_type_raw) {
            SvcMessage::Bad => {
                // A zero byte is only valid as trailing padding. If everything
                // that remains is zero, consume it and finish cleanly.
                let mut probe = *reader;
                let mut all_zero = true;
                while probe.bits_remaining() >= 8 {
                    if probe.read_u8() != 0 {
                        all_zero = false;
                        break;
                    }
                }
                if all_zero {
                    reader.skip_bits(reader.bits_remaining());
                    Ok(())
                } else {
                    Err("SVC_BAD mid-stream".to_string())
                }
            }
            SvcMessage::Nop | SvcMessage::Choke => Ok(()),
            SvcMessage::Damage => Ok(()),
            SvcMessage::KilledMonster | SvcMessage::FoundSecret | SvcMessage::Intermission => {
                Ok(())
            }
            SvcMessage::Disconnect => {
                let _ = reader.read_string();
                Ok(())
            }
            SvcMessage::Event => parse_event(reader, event_parser),
            SvcMessage::Version => {
                reader.skip_bits(32);
                Ok(())
            }
            SvcMessage::SetView => {
                let target = reader.read_bits(16) as u16;
                event_parser.set_observer_target(target);
                Ok(())
            }
            SvcMessage::Sound => parse_sound(reader).map(|sound| {
                event_parser.network_sounds.push(NetworkSound {
                    time: event_parser.current_time,
                    ..sound
                });
            }),
            SvcMessage::Time => {
                reader.skip_bits(32);
                Ok(())
            }
            SvcMessage::Print | SvcMessage::StuffText | SvcMessage::CenterPrint => {
                let _ = reader.read_string();
                Ok(())
            }
            SvcMessage::SetAngle => {
                reader.skip_bits(48);
                Ok(())
            }
            SvcMessage::ServerInfo => parse_server_info(reader, state),
            SvcMessage::LightStyle => {
                reader.skip_bits(8);
                let _ = reader.read_string();
                Ok(())
            }
            SvcMessage::UpdateUserInfo => {
                let slot = reader.read_u8();
                reader.skip_bits(32); // userid
                let userinfo = reader.read_string();
                reader.skip_bits(128); // CD key hash

                if let Some(name) = parse_userinfo_name(&userinfo) {
                    event_parser.register_player(slot, name);
                }
                if let Some(model) = parse_userinfo_field(&userinfo, "model") {
                    let prev = event_parser.get_player_model(slot);
                    let changed = prev.as_deref().map_or(true, |p| p != model);
                    event_parser.register_player_model(slot, model.clone());
                    // Emit a timeline event so the UI can track side switches
                    // (halftime) and color players correctly over time.
                    if changed {
                        if let Some(name) = event_parser.get_player_name(slot) {
                            let time = event_parser.current_time;
                            event_parser.events.push(crate::types::GameEvent {
                                time,
                                event_type: crate::types::GameEventType::ModelChange,
                                data: crate::types::GameEventData {
                                    player: Some(name),
                                    model: Some(model),
                                    killer: None,
                                    victim: None,
                                    weapon: None,
                                    headshot: false,
                                    message: None,
                                    winner: None,
                                    team: None,
                                    score: None,
                                    round_time: None,
                                },
                            });
                        }
                    }
                }
                Ok(())
            }
            SvcMessage::DeltaDescription => parse_delta_description(reader),
            SvcMessage::ClientData => parse_client_data(reader),
            SvcMessage::StopSound => {
                reader.skip_bits(16);
                Ok(())
            }
            SvcMessage::Pings => {
                while reader.bits_remaining() > 24 && reader.read_bit() {
                    reader.skip_bits(24); // slot, ping, loss
                }
                reader.byte_align();
                Ok(())
            }
            SvcMessage::Particle => {
                // origin (3 x 16-bit coord), direction (3 bytes), count, color
                reader.skip_bits(3 * 16 + 3 * 8 + 8 + 8);
                Ok(())
            }
            SvcMessage::SpawnStatic => {
                reader.skip_bytes(18);
                let render_mode = reader.read_u8();
                if render_mode != 0 {
                    reader.skip_bytes(5);
                }
                Ok(())
            }
            SvcMessage::EventReliable => parse_event_reliable(reader),
            SvcMessage::SpawnBaseline => parse_spawn_baseline(reader, state).map(|_| ()),
            SvcMessage::TempEntity => parse_temp_entity(reader).map(|effect| {
                if let Some(effect) = effect {
                    event_parser.temp_effects.push(TempEffect {
                        time: event_parser.current_time,
                        ..effect
                    });
                }
            }),
            SvcMessage::SetPause | SvcMessage::SignonNum => {
                reader.skip_bits(8);
                Ok(())
            }
            SvcMessage::SpawnStaticSound => {
                // origin (3 x 16-bit), sound index (16), volume (8),
                // attenuation (8), entity index (16), pitch (8), flags (8)
                reader.skip_bits(3 * 16 + 16 + 8 + 8 + 16 + 8 + 8);
                Ok(())
            }
            SvcMessage::Finale | SvcMessage::CutScene => {
                let _ = reader.read_string();
                Ok(())
            }
            SvcMessage::CdTrack => {
                reader.skip_bits(16);
                Ok(())
            }
            SvcMessage::Restore => {
                let _ = reader.read_string(); // save name
                let count = reader.read_u8();
                for _ in 0..count {
                    let _ = reader.read_string();
                }
                Ok(())
            }
            SvcMessage::WeaponAnim => {
                reader.skip_bits(16);
                Ok(())
            }
            SvcMessage::DecalName => {
                reader.skip_bits(8);
                let _ = reader.read_string();
                Ok(())
            }
            SvcMessage::RoomType => {
                reader.skip_bits(16);
                Ok(())
            }
            SvcMessage::AddAngle => {
                reader.skip_bits(16);
                Ok(())
            }
            SvcMessage::NewUserMsg => {
                let msg_id = reader.read_u8();
                let size = reader.read_u8() as i8;
                let name_bytes = reader.read_bytes(16);
                let name = String::from_utf8_lossy(&name_bytes)
                    .trim_end_matches('\0')
                    .to_string();
                event_parser.register_user_message(msg_id, name, size);
                Ok(())
            }
            SvcMessage::PacketEntities => {
                parse_packet_entities(reader, state, false, debug).map(|_| ())
            }
            SvcMessage::DeltaPacketEntities => {
                parse_packet_entities(reader, state, true, debug).map(|_| ())
            }
            SvcMessage::ResourceList => skip_resource_list(reader),
            SvcMessage::NewMoveVars => {
                // 16 floats, footsteps byte, rollangle/rollspeed/skycolor/skyvec
                // (8 floats), then sky name string
                reader.skip_bits(16 * 32);
                reader.skip_bits(8);
                reader.skip_bits(8 * 32);
                let _ = reader.read_string();
                Ok(())
            }
            SvcMessage::ResourceRequest => {
                reader.skip_bits(64); // spawn count + reserved
                Ok(())
            }
            SvcMessage::Customization => {
                reader.skip_bits(8); // player index
                reader.skip_bits(8); // type
                let _ = reader.read_string(); // name
                reader.skip_bits(16); // index
                reader.skip_bits(32); // download size
                let flags = reader.read_u8();
                if flags & 4 != 0 {
                    reader.skip_bytes(16); // md5 hash
                }
                Ok(())
            }
            SvcMessage::CrosshairAngle => {
                reader.skip_bits(16);
                Ok(())
            }
            SvcMessage::SoundFade => {
                reader.skip_bits(32);
                Ok(())
            }
            SvcMessage::FileTxferFailed => {
                let _ = reader.read_string();
                Ok(())
            }
            SvcMessage::Hltv => {
                let sub = reader.read_u8();
                match sub {
                    0 => {
                        // HLTV_ACTIVE: this stream is an HLTV spectator stream
                        IS_HLTV.with(|c| c.set(true));
                        Ok(())
                    }
                    2 => {
                        // HLTV_LISTEN / HLTV_CAMERA
                        reader.skip_bytes(8);
                        Ok(())
                    }
                    _ => Err(format!("unknown HLTV subcommand {}", sub)),
                }
            }
            SvcMessage::Director => {
                let len = reader.read_u8();
                let data = reader.read_bytes(len as usize);
                if let Some(command) = data.first().copied() {
                    match command {
                        // DRC_CMD_EVENT: primary entity, secondary entity,
                        // event flags. The primary entity is the recorded
                        // subject selected by the director.
                        2 if data.len() >= 5 => {
                            let primary = u16::from_le_bytes([data[1], data[2]]);
                            if primary <= max_clients() {
                                event_parser.set_observer_target(primary);
                            }
                        }
                        // DRC_CMD_MODE: observer camera mode byte.
                        3 if data.len() >= 2 => {
                            event_parser.set_observer_mode(data[1]);
                        }
                        _ => {}
                    }
                }
                Ok(())
            }
            SvcMessage::VoiceInit => {
                let _ = reader.read_string();
                reader.skip_bits(8); // quality (protocol >= 47)
                Ok(())
            }
            SvcMessage::VoiceData => {
                reader.skip_bits(8); // player index
                let length = reader.read_bits(16);
                reader.skip_bits(length as usize * 8);
                Ok(())
            }
            SvcMessage::SendExtraInfo => {
                let _ = reader.read_string();
                reader.skip_bits(8);
                Ok(())
            }
            SvcMessage::TimeScale => {
                reader.skip_bits(32);
                Ok(())
            }
            SvcMessage::ResourceLocation | SvcMessage::SendCvarValue => {
                let _ = reader.read_string();
                Ok(())
            }
            SvcMessage::SendCvarValue2 => {
                reader.skip_bits(32); // request id
                let _ = reader.read_string();
                Ok(())
            }
        };

        if let Err(e) = result {
            let log_it = debug
                || DESYNC_LOGS.with(|c| {
                    let n = c.get();
                    c.set(n + 1);
                    n < 10
                });
            if log_it {
                let remaining = reader.peek_bytes(16);
                crate::console_log!(
                    "  SVC {} desync (msg #{}) : {}; history={:?}; next bytes: {:02x?}",
                    msg_type_raw,
                    msg_count,
                    e,
                    history,
                    remaining
                );
            }
            clean = false;
            break;
        }

        msg_count += 1;
        if msg_count > 4096 {
            clean = false;
            break;
        }
    }

    Ok(clean)
}

/// Parse a registered user message and hand it to the event parser.
fn parse_user_message(
    reader: &mut BitReader,
    event_parser: &mut EventParser,
    msg_type_raw: u8,
) -> Result<(), String> {
    let size = event_parser
        .get_message_size(msg_type_raw)
        .ok_or_else(|| format!("unregistered user message {}", msg_type_raw))?;

    let msg_len = if size < 0 {
        reader.read_u8() as usize
    } else {
        size as usize
    };

    if msg_len >= 256 || reader.bits_remaining() < msg_len * 8 {
        return Err(format!(
            "user message {} length {} overflows",
            msg_type_raw, msg_len
        ));
    }

    let msg_data = reader.read_bytes(msg_len);
    event_parser.parse_user_message(msg_type_raw, &msg_data);
    Ok(())
}

/// Parse an arbitrary key from a userinfo string
fn parse_userinfo_field(userinfo: &str, key: &str) -> Option<String> {
    let parts: Vec<&str> = userinfo.split('\\').collect();
    for i in 0..parts.len() {
        if parts[i] == key && i + 1 < parts.len() && !parts[i + 1].is_empty() {
            return Some(parts[i + 1].to_string());
        }
    }
    None
}

/// Parse player name from userinfo string
fn parse_userinfo_name(userinfo: &str) -> Option<String> {
    let parts: Vec<&str> = userinfo.split('\\').collect();
    for i in 0..parts.len() {
        if parts[i] == "name" && i + 1 < parts.len() {
            let name = parts[i + 1].to_string();
            if !name.is_empty() && !name.contains("HLTV") {
                return Some(name);
            }
        }
    }
    None
}

// === Message parsers ===

/// SVC_SERVERINFO
fn parse_server_info(reader: &mut BitReader, state: &mut EntityState) -> Result<(), String> {
    reader.skip_bits(32); // protocol
    reader.skip_bits(32); // spawn count
    reader.skip_bits(32); // map checksum
    reader.skip_bytes(16); // client.dll hash
    let max_players = reader.read_u8();
    if (1..=64).contains(&max_players) {
        MAX_CLIENTS.with(|c| c.set(max_players as u16));
        state.set_max_players(max_players as u16);
    }
    reader.skip_bits(8); // player index
    reader.skip_bits(8); // coop/deathmatch flag
    let _ = reader.read_string(); // game dir
    let _ = reader.read_string(); // hostname
    let _ = reader.read_string(); // map name
    let _ = reader.read_string(); // map cycle
                                  // Crypt key: flag byte, and if non-zero, 21 bytes of key data follow
    let has_crypt_key = reader.read_u8();
    if has_crypt_key > 0 {
        reader.skip_bytes(21);
    }
    Ok(())
}

/// SVC_DELTADESCRIPTION: learn a delta definition. Entries are delta-encoded
/// against the hardcoded delta_description_t meta-definition.
fn parse_delta_description(reader: &mut BitReader) -> Result<(), String> {
    let name = reader.read_string();
    let num_fields = reader.read_bits(16) as usize;

    let is_valid_name = !name.is_empty()
        && name.len() < 64
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '[' || c == ']');
    if !is_valid_name || num_fields == 0 || num_fields > 256 {
        return Err(format!(
            "invalid delta description '{}' with {} fields",
            name, num_fields
        ));
    }

    let meta = meta_delta_description();
    let mut definition = DeltaDefinition::new(name);

    for _ in 0..num_fields {
        let mut field_name = String::new();
        let mut bits = 0u32;
        let mut divisor = 1.0f32;
        let mut pre_multiplier = 1.0f32;
        let mut flags = 0u32;

        read_delta(reader, &meta, |meta_field, value| {
            match (meta_field.name.as_str(), value) {
                ("name", DeltaVal::Str(s)) => field_name = s,
                ("nBits", DeltaVal::Num(v)) => bits = v as u32,
                ("divisor", DeltaVal::Num(v)) => divisor = v as f32,
                ("preMultiplier", DeltaVal::Num(v)) => pre_multiplier = v as f32,
                ("flags", DeltaVal::Num(v)) => flags = v as u32,
                _ => {}
            }
        })?;

        if field_name.is_empty() || bits == 0 || bits > 32 {
            return Err(format!(
                "invalid delta field '{}' ({} bits) in description",
                field_name, bits
            ));
        }

        let divisor = if divisor.is_finite() && divisor != 0.0 {
            divisor
        } else {
            1.0
        };
        let pre_multiplier = if pre_multiplier.is_finite() {
            pre_multiplier
        } else {
            1.0
        };
        definition.add_field(DeltaFieldDef::new(
            field_name,
            bits as u8,
            divisor,
            pre_multiplier,
            flags,
        ));
    }

    reader.byte_align();

    crate::console_log!(
        "  DeltaDescription: {} ({} fields)",
        definition.name,
        definition.fields.len()
    );
    DELTA_REGISTRY.with(|reg| {
        reg.borrow_mut().register(definition);
    });

    Ok(())
}

/// SVC_CLIENTDATA
fn parse_client_data(reader: &mut BitReader) -> Result<(), String> {
    // HLTV streams carry no client data body
    if IS_HLTV.with(|c| c.get()) {
        return Ok(());
    }

    if reader.read_bit() {
        reader.skip_bits(8); // delta sequence
    }

    let clientdata = get_def("clientdata_t")?;
    skip_delta(reader, &clientdata)?;

    let weapon_data = get_def("weapon_data_t")?;
    while reader.bits_remaining() > 6 && reader.read_bit() {
        reader.skip_bits(6); // weapon index (protocol >= 47)
        skip_delta(reader, &weapon_data)?;
    }

    reader.byte_align();
    Ok(())
}

/// SVC_EVENT
fn parse_event(reader: &mut BitReader, event_parser: &mut EventParser) -> Result<(), String> {
    EVENT_STATS.with(|c| {
        let (a, b) = c.get();
        c.set((a + 1, b));
    });
    let num_events = reader.read_bits(5);
    let event_def = get_def("event_t")?;

    for _ in 0..num_events {
        let event_index = reader.read_bits(10) as u16;
        let mut entindex: i64 = 0;
        let mut packet_index: Option<usize> = None;
        if reader.read_bit() {
            packet_index = Some(reader.read_bits(11) as usize);
            if reader.read_bit() {
                read_delta(reader, &event_def, |field, value| {
                    if field.name == "entindex" {
                        if let DeltaVal::Num(v) = value {
                            entindex = v as i64;
                        }
                    }
                })?;
            }
        }
        if reader.read_bit() {
            reader.skip_bits(16); // fire time
        }

        EVENT_STATS.with(|c| {
            let (a, b) = c.get();
            c.set((a, b + (entindex > 0) as u32));
        });
        // Shooter: explicit entindex when sane, else resolve the packet index
        // against the frame's reconstructed entity list
        if !(1..=64).contains(&entindex) {
            if let Some(pi) = packet_index {
                let resolved = LAST_PACKET_ORDER.with(|o| o.borrow().get(pi).copied());
                if let Some(ent) = resolved {
                    entindex = ent as i64;
                }
            }
        }

        // Weapon fire scripts ("events/ak47.sc") with a valid shooter
        if entindex > 0 && entindex <= 64 {
            let is_fire = EVENT_NAMES.with(|m| {
                m.borrow().get(&event_index).map_or(false, |n| {
                    n.starts_with("events/")
                        && !n.contains("door")
                        && !n.contains("train")
                        && !n.contains("vehicle")
                        && !n.contains("glass")
                })
            });
            if is_fire {
                event_parser
                    .shots
                    .push((event_parser.current_time, (entindex - 1) as u8));
            }
        }
    }

    reader.byte_align();
    Ok(())
}

/// SVC_EVENT_RELIABLE
fn parse_event_reliable(reader: &mut BitReader) -> Result<(), String> {
    let event_def = get_def("event_t")?;
    reader.skip_bits(10); // event index
    skip_delta(reader, &event_def)?;
    if reader.read_bit() {
        reader.skip_bits(16); // delay
    }
    reader.byte_align();
    Ok(())
}

/// SVC_SPAWNBASELINE
fn parse_spawn_baseline(reader: &mut BitReader, state: &mut EntityState) -> Result<usize, String> {
    let mut count = 0;

    loop {
        if reader.bits_remaining() < 16 {
            return Err("spawn baseline ran out of data".to_string());
        }
        let index = reader.read_bits(11) as u16;
        if index == 0x7FF {
            break;
        }

        let entity_type = reader.read_bits(2);
        let def_name = if entity_type & 1 != 0 {
            if index >= 1 && index <= max_clients() {
                "entity_state_player_t"
            } else {
                "entity_state_t"
            }
        } else {
            "custom_entity_state_t"
        };

        let def = get_def(def_name)?;
        let delta = read_entity_delta(reader, &def)?;

        let mut entity = Entity::new(index);
        entity.active = true;
        delta.apply_to(&mut entity);
        state.set_baseline(index, entity);

        count += 1;
        if count > 4096 {
            return Err("spawn baseline entity count overflow".to_string());
        }
    }

    // Footer: 5 bits, all ones
    let footer = reader.read_bits(5);
    if footer != 0x1F {
        return Err(format!("bad spawn baseline footer {:#x}", footer));
    }

    // Instanced baselines (extra entity_state_t deltas)
    let n_extra = reader.read_bits(6);
    if n_extra > 0 {
        let def = get_def("entity_state_t")?;
        for _ in 0..n_extra {
            skip_delta(reader, &def)?;
        }
    }

    reader.byte_align();
    Ok(count)
}

/// SVC_PACKETENTITIES (is_delta=false) / SVC_DELTAPACKETENTITIES (is_delta=true)
fn parse_packet_entities(
    reader: &mut BitReader,
    state: &mut EntityState,
    is_delta: bool,
    debug: bool,
) -> Result<usize, String> {
    let result = parse_packet_entities_inner(reader, state, is_delta, debug);
    if result.is_ok() {
        LAST_PACKET_ORDER.with(|o| *o.borrow_mut() = state.active_indices_sorted());
    }
    result
}

fn parse_packet_entities_inner(
    reader: &mut BitReader,
    state: &mut EntityState,
    is_delta: bool,
    debug: bool,
) -> Result<usize, String> {
    let _num_entities = reader.read_bits(16);
    if is_delta {
        reader.skip_bits(8); // delta sequence number
    }

    let mut entity_index = 0u16;
    let mut count = 0usize;
    let mut player_updates = 0usize;

    loop {
        if reader.bits_remaining() < 16 {
            return Err("packet entities ran out of data".to_string());
        }
        // A 16-bit zero word marks the end of the entity list
        if reader.peek_bits(16) == 0 {
            reader.skip_bits(16);
            break;
        }

        let mut remove = false;
        if is_delta {
            remove = reader.read_bit();
            let absolute = reader.read_bit();
            if absolute {
                entity_index = reader.read_bits(11) as u16;
            } else {
                entity_index = entity_index.wrapping_add(reader.read_bits(6) as u16);
            }
        } else {
            let increment = reader.read_bit();
            if increment {
                entity_index = entity_index.wrapping_add(1);
            } else {
                let absolute = reader.read_bit();
                if absolute {
                    entity_index = reader.read_bits(11) as u16;
                } else {
                    entity_index = entity_index.wrapping_add(reader.read_bits(6) as u16);
                }
            }
        }

        if entity_index > 2048 {
            return Err(format!("invalid entity index {}", entity_index));
        }

        if remove {
            state.remove_entity(entity_index);
        } else {
            let custom = reader.read_bit();
            if !is_delta {
                // Full update may reference an instanced baseline
                if reader.read_bit() {
                    reader.skip_bits(6); // baseline index
                }
            }

            let def = get_def(packet_entity_def_name(entity_index, custom))?;
            let delta = read_entity_delta(reader, &def)?;

            if entity_index >= 1 && entity_index <= max_clients() {
                player_updates += 1;
                if debug && player_updates <= 3 {
                    crate::console_log!(
                        "      Player {}: origin=[{:?}, {:?}, {:?}]",
                        entity_index,
                        delta.origin[0],
                        delta.origin[1],
                        delta.origin[2]
                    );
                }
            }

            state.apply_delta(entity_index, delta);
        }

        count += 1;
        if count > 4096 {
            return Err("packet entities count overflow".to_string());
        }
    }

    reader.byte_align();

    if debug && count > 0 {
        crate::console_log!(
            "      PacketEntities(delta={}): {} entities, {} player updates",
            is_delta,
            count,
            player_updates
        );
    }

    Ok(count)
}

/// SVC_SOUND. Defaults mirror the GoldSrc mixer when optional fields are absent.
fn parse_sound(reader: &mut BitReader) -> Result<NetworkSound, String> {
    let flags = reader.read_bits(9);
    let volume = if flags & (1 << 0) != 0 {
        reader.read_u8() as f32 / 255.0
    } else {
        1.0
    };
    let attenuation = if flags & (1 << 1) != 0 {
        reader.read_u8() as f32 / 64.0
    } else {
        0.8
    };
    let channel = reader.read_bits(3) as u8;
    let entity = reader.read_bits(11) as u16;
    let index = if flags & (1 << 2) != 0 {
        reader.read_bits(16) as u16
    } else {
        reader.read_bits(8) as u16
    };
    let (x, y, z) = reader.read_coord_vec();
    let pitch = if flags & (1 << 3) != 0 {
        reader.read_u8()
    } else {
        100
    };
    reader.byte_align();
    Ok(NetworkSound {
        time: 0.0,
        sample: sound_name(index).unwrap_or_else(|| format!("#{index}")),
        origin: Vec3::new(x, y, z),
        volume,
        attenuation,
        pitch,
        entity,
        channel,
    })
}

/// SVC_RESOURCELIST
fn skip_resource_list(reader: &mut BitReader) -> Result<(), String> {
    let num_resources = reader.read_bits(12);
    if num_resources > 2048 {
        return Err(format!("implausible resource count {}", num_resources));
    }

    for _ in 0..num_resources {
        if reader.bits_remaining() < 44 {
            return Err("resource list ran out of data".to_string());
        }
        let res_type = reader.read_bits(4); // 2 = t_model
        let name = reader.read_string();
        let index = reader.read_bits(12) as u16;
        if res_type == 0 && !name.is_empty() {
            SOUND_NAMES.with(|m| m.borrow_mut().insert(index, name));
        } else if res_type == 2 && !name.is_empty() {
            MODEL_NAMES.with(|m| m.borrow_mut().insert(index, name));
        } else if res_type == 5 && !name.is_empty() {
            // Event precache indices are 1-based sequential in resource order,
            // independent of the resource index field
            EVENT_NAMES.with(|m| {
                let mut m = m.borrow_mut();
                if !m.values().any(|v| v == &name) {
                    let seq = m.len() as u16 + 1;
                    m.insert(seq, name);
                }
            });
        }
        reader.skip_bits(24); // download size
        let flags = reader.read_bits(3);
        if flags & 4 != 0 {
            reader.skip_bytes(16); // md5 hash
        }
        if reader.read_bit() {
            reader.skip_bytes(32); // reserved data
        }
    }

    // Consistency list
    if reader.read_bit() {
        while reader.bits_remaining() > 10 && reader.read_bit() {
            let n_bits = if reader.read_bit() { 5 } else { 10 };
            reader.skip_bits(n_bits);
        }
    }

    reader.byte_align();
    Ok(())
}

fn coord_from(raw: &[u8], offset: usize) -> f32 {
    if offset + 2 > raw.len() {
        return 0.0;
    }
    i16::from_le_bytes([raw[offset], raw[offset + 1]]) as f32 / 8.0
}

fn vec_from(raw: &[u8], offset: usize) -> Vec3 {
    Vec3::new(
        coord_from(raw, offset),
        coord_from(raw, offset + 2),
        coord_from(raw, offset + 4),
    )
}

/// SVC_TEMPENTITY: preserve the effect kind and its useful spatial payload
/// while consuming every legacy format exactly.
fn parse_temp_entity(reader: &mut BitReader) -> Result<Option<TempEffect>, String> {
    let te_type = reader.read_u8();

    // Payload sizes in bytes (from the HL SDK / coldemoplayer)
    let bytes: usize = match te_type {
        0 => 24, // TE_BEAMPOINTS
        1 => 20, // TE_BEAMENTPOINT
        2 => 6,  // TE_GUNSHOT
        3 => 11, // TE_EXPLOSION
        4 => 6,  // TE_TAREXPLOSION
        5 => 10, // TE_SMOKE
        6 => 12, // TE_TRACER
        7 => 17, // TE_LIGHTNING
        8 => 16, // TE_BEAMENTS
        9 => 6,  // TE_SPARKS
        10 => 6, // TE_LAVASPLASH
        11 => 6, // TE_TELEPORT
        12 => 8, // TE_EXPLOSION2
        13 => {
            // TE_BSPDECAL: 8 bytes, then entity index; if non-zero, 2 more bytes
            let mut raw = reader.read_bytes(8);
            let entity_index = reader.read_bits(16);
            if entity_index != 0 {
                raw.extend(reader.read_bytes(2));
            }
            return Ok(Some(TempEffect {
                time: 0.0,
                kind: te_type,
                origin: vec_from(&raw, 0),
                end: Vec3::zero(),
                color: 0,
                scale: 0,
            }));
        }
        14 => 9,       // TE_IMPLOSION
        15 => 19,      // TE_SPRITETRAIL
        16 => 0,       // TE_BEAM (obsolete)
        17 => 10,      // TE_SPRITE
        18 => 16,      // TE_BEAMSPRITE
        19..=21 => 24, // TE_BEAMTORUS, TE_BEAMDISK, TE_BEAMCYLINDER
        22 => 10,      // TE_BEAMFOLLOW
        23 => 11,      // TE_GLOWSPRITE
        24 => 16,      // TE_BEAMRING
        25 => 19,      // TE_STREAK_SPLASH
        26 => 0,       // TE_BEAMHOSE (obsolete)
        27 => 12,      // TE_DLIGHT
        28 => 16,      // TE_ELIGHT
        29 => {
            // TE_TEXTMESSAGE
            reader.skip_bytes(5);
            let effect = reader.read_u8();
            reader.skip_bytes(14);
            if effect == 2 {
                reader.skip_bytes(2);
            }
            let _ = reader.read_string();
            return Ok(None);
        }
        30 | 31 => 17,   // TE_LINE, TE_BOX
        99 => 2,         // TE_KILLBEAM
        100 => 10,       // TE_LARGEFUNNEL
        101 => 14,       // TE_BLOODSTREAM
        102 => 12,       // TE_SHOWLINE
        103 => 14,       // TE_BLOOD
        104 => 9,        // TE_DECAL
        105 => 5,        // TE_FIZZ
        106 => 17,       // TE_MODEL
        107 => 13,       // TE_EXPLODEMODEL
        108 => 24,       // TE_BREAKMODEL
        109 => 9,        // TE_GUNSHOTDECAL
        110 => 17,       // TE_SPRITE_SPRAY
        111 => 7,        // TE_ARMOR_RICOCHET
        112 => 10,       // TE_PLAYERDECAL
        113 | 114 => 19, // TE_BUBBLES, TE_BUBBLETRAIL
        115 => 12,       // TE_BLOODSPRITE
        116 | 117 => 7,  // TE_WORLDDECAL, TE_WORLDDECALHIGH
        118 => 9,        // TE_DECALHIGH
        119 => 16,       // TE_PROJECTILE
        120 => 18,       // TE_SPRAY
        121 => 5,        // TE_PLAYERSPRITES
        122 => 10,       // TE_PARTICLEBURST
        123 => 9,        // TE_FIREFIELD
        124 => 7,        // TE_PLAYERATTACHMENT
        125 => 1,        // TE_KILLPLAYERATTACHMENTS
        126 => 18,       // TE_MULTIGUNSHOT
        127 => 15,       // TE_USERTRACER
        other => return Err(format!("unknown temp entity type {}", other)),
    };

    let raw = reader.read_bytes(bytes);
    let spatial = matches!(
        te_type,
        0..=15 | 17..=25 | 27..=28 | 30..=31 | 100..=124 | 126..=127
    );
    if !spatial || raw.len() < 6 {
        return Ok(None);
    }
    let end = if matches!(te_type, 0 | 6..=8 | 18..=25 | 30..=31 | 102 | 113..=114 | 126..=127)
        && raw.len() >= 12
    {
        vec_from(&raw, 6)
    } else {
        Vec3::zero()
    };
    let color = match te_type {
        27 if raw.len() >= 10 => ((raw[7] as u32) << 16) | ((raw[8] as u32) << 8) | raw[9] as u32,
        101 | 103 if raw.len() >= 13 => raw[12] as u32,
        _ => 0,
    };
    let scale = match te_type {
        3 | 5 if raw.len() >= 9 => raw[8],
        27 if raw.len() >= 7 => raw[6],
        _ => 0,
    };
    Ok(Some(TempEffect {
        time: 0.0,
        kind: te_type,
        origin: vec_from(&raw, 0),
        end,
        color,
        scale,
    }))
}
