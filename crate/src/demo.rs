use crate::netmsg;
use crate::types::*;
use byteorder::{LittleEndian, ReadBytesExt};
use std::io::{Cursor, Read, Seek, SeekFrom};

pub struct DemoParser<'a> {
    data: Cursor<&'a [u8]>,
}

impl<'a> DemoParser<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Self {
            data: Cursor::new(data),
        }
    }

    pub fn parse(&mut self) -> Result<ParsedDemo, String> {
        let header = self.parse_header()?;

        let directory = self.parse_directory(header.directory_offset)?;
        let (frames, mut players, demo_buffers, buffer_anchors) =
            self.parse_frames_with_players(&directory)?;

        // Always scan the entire file for players (frame parsing is unreliable)
        let data = self.data.get_ref();
        let mut player_map: std::collections::HashMap<u8, PlayerInfo> =
            std::collections::HashMap::new();
        Self::extract_player_info(data, &mut player_map);
        players = player_map.into_values().collect();

        Ok(ParsedDemo {
            header,
            directory,
            frames,
            players,
            demo_buffers,
            buffer_anchors,
        })
    }

    fn parse_header(&mut self) -> Result<DemoHeader, String> {
        let mut magic_bytes = [0u8; 8];
        self.data
            .read_exact(&mut magic_bytes)
            .map_err(|e| e.to_string())?;
        let magic = String::from_utf8_lossy(&magic_bytes)
            .trim_end_matches('\0')
            .to_string();

        if !magic.starts_with("HLDEMO") {
            return Err(format!("Invalid magic: {}", magic));
        }

        let demo_protocol = self
            .data
            .read_i32::<LittleEndian>()
            .map_err(|e| e.to_string())?;
        let network_protocol = self
            .data
            .read_i32::<LittleEndian>()
            .map_err(|e| e.to_string())?;
        let map_name = self.read_string(260)?;
        let game_dir = self.read_string(260)?;
        let _map_crc = self
            .data
            .read_u32::<LittleEndian>()
            .map_err(|e| e.to_string())?;
        let directory_offset = self
            .data
            .read_i32::<LittleEndian>()
            .map_err(|e| e.to_string())?;

        Ok(DemoHeader {
            magic,
            demo_protocol,
            network_protocol,
            map_name,
            game_dir,
            directory_offset,
        })
    }

    fn parse_directory(&mut self, offset: i32) -> Result<Vec<DirectoryEntry>, String> {
        self.data
            .seek(SeekFrom::Start(offset as u64))
            .map_err(|e| e.to_string())?;
        let entry_count = self
            .data
            .read_i32::<LittleEndian>()
            .map_err(|e| e.to_string())?;
        let mut entries = Vec::with_capacity(entry_count as usize);

        for _ in 0..entry_count {
            entries.push(DirectoryEntry {
                entry_type: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                description: self.read_string(64)?,
                flags: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                cd_track: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                track_time: self
                    .data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                frame_count: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                offset: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
                file_length: self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?,
            });
        }

        Ok(entries)
    }

    fn parse_frames_with_players(
        &mut self,
        directory: &[DirectoryEntry],
    ) -> Result<
        (
            Vec<DemoFrame>,
            Vec<PlayerInfo>,
            Vec<(f32, Vec<u8>)>,
            Vec<(u64, f32)>,
        ),
        String,
    > {
        let mut frames = Vec::new();
        let mut players: std::collections::HashMap<u8, PlayerInfo> =
            std::collections::HashMap::new();
        let mut demo_buffers: Vec<(f32, Vec<u8>)> = Vec::new();
        let mut anchors: Vec<(u64, f32)> = Vec::new();

        for entry in directory.iter() {
            if entry.entry_type == 0 || entry.entry_type == 1 {
                self.data
                    .seek(SeekFrom::Start(entry.offset as u64))
                    .map_err(|e| e.to_string())?;
                let end_offset = entry.offset as u64 + entry.file_length as u64;
                let mut frame_count = 0;

                while self.data.position() < end_offset {
                    match self.parse_frame_with_buffer() {
                        Ok(Some((frame, buffer_data))) => {
                            let is_next_section = frame.frame_type == FrameType::NextSection;

                            // Parse player info and collect network data
                            if let Some(data) = buffer_data {
                                Self::extract_player_info(&data, &mut players);
                                // Collect network data from both NetMsg and DemoBuffer frames
                                let is_netmsg = frame.frame_type == FrameType::NetMsg
                                    || frame.frame_type == FrameType::NetMsgStart;
                                let is_demobuffer = frame.frame_type == FrameType::DemoBuffer;
                                if (is_netmsg || is_demobuffer) && data.len() > 20 {
                                    // File-offset -> frame-time anchor for the
                                    // byte-position event scans
                                    anchors.push((self.data.position(), frame.time));
                                    demo_buffers.push((frame.time, data));
                                }
                            }

                            frames.push(frame);
                            frame_count += 1;
                            if is_next_section {
                                break;
                            }
                        }
                        Ok(None) | Err(_) => {
                            break;
                        }
                    }
                }
            }
        }

        let player_list: Vec<PlayerInfo> = players.into_values().collect();
        anchors.sort_by_key(|(o, _)| *o);
        Ok((frames, player_list, demo_buffers, anchors))
    }

    fn extract_player_info(data: &[u8], players: &mut std::collections::HashMap<u8, PlayerInfo>) {
        // Try to find valid UTF-8 sequences containing \name\
        let needle = b"\\name\\";
        let mut found_count = 0;
        let mut i = 0;

        while i + needle.len() < data.len() {
            if &data[i..i + needle.len()] == needle {
                found_count += 1;
                // Found \name\, try to extract the surrounding userinfo string
                // Look backwards for start of string
                let mut start = i;
                while start > 0 && data[start - 1] >= 0x20 && data[start - 1] < 0x7f {
                    start -= 1;
                }
                // Look forward for end of string (null terminator or non-printable)
                let mut end = i + needle.len();
                while end < data.len() && data[end] >= 0x20 && data[end] < 0x7f {
                    end += 1;
                }

                if let Ok(userinfo) = std::str::from_utf8(&data[start..end]) {
                    let info = Self::parse_userinfo(userinfo);
                    if let Some(name) = info.get("name") {
                        if !name.is_empty() && !name.contains("HLTV") {
                            let index = players.len() as u8;
                            // Use name as key to avoid duplicates
                            let key = name.as_bytes().iter().fold(0u8, |a, b| a.wrapping_add(*b));
                            if !players.contains_key(&key) {
                                players.insert(
                                    key,
                                    PlayerInfo {
                                        index,
                                        name: name.clone(),
                                        team: info.get("team").cloned().unwrap_or_default(),
                                        model: info.get("model").cloned().unwrap_or_default(),
                                    },
                                );
                            }
                        }
                    }
                }
                i = end.max(i + 1);
            } else {
                i += 1;
            }
        }
    }

    fn extract_from_text(text: &str, players: &mut std::collections::HashMap<u8, PlayerInfo>) {
        for segment in text.split('\0') {
            if segment.contains("\\name\\") && !segment.contains("HLTV") {
                let info = Self::parse_userinfo(segment);
                if let Some(name) = info.get("name") {
                    if !name.is_empty() {
                        let index = players.len() as u8;
                        let key = name.as_bytes().iter().fold(0u8, |a, b| a.wrapping_add(*b));
                        players.entry(key).or_insert(PlayerInfo {
                            index,
                            name: name.clone(),
                            team: info.get("team").cloned().unwrap_or_default(),
                            model: info.get("model").cloned().unwrap_or_default(),
                        });
                    }
                }
            }
        }
    }

    fn parse_userinfo(s: &str) -> std::collections::HashMap<String, String> {
        let mut result = std::collections::HashMap::new();
        // Split by \ and filter out empty parts
        let parts: Vec<&str> = s.split('\\').filter(|p| !p.is_empty()).collect();
        let mut i = 0;
        while i + 1 < parts.len() {
            result.insert(parts[i].to_string(), parts[i + 1].to_string());
            i += 2;
        }
        result
    }

    fn parse_frame_with_buffer(&mut self) -> Result<Option<(DemoFrame, Option<Vec<u8>>)>, String> {
        let pos_before = self.data.position();

        // Peek at raw bytes for debugging
        let mut peek_bytes = [0u8; 12];
        let _ = self.data.read_exact(&mut peek_bytes);
        self.data
            .seek(SeekFrom::Start(pos_before))
            .map_err(|e| e.to_string())?;

        // Frame type is 1 byte (u8) in GoldSrc demos
        let frame_type_raw = self.data.read_u8().map_err(|e| e.to_string())? as i32;
        let frame_type = FrameType::from(frame_type_raw);
        let time = self
            .data
            .read_f32::<LittleEndian>()
            .map_err(|e| e.to_string())?;
        let frame = self
            .data
            .read_i32::<LittleEndian>()
            .map_err(|e| e.to_string())?;

        let mut demo_frame = DemoFrame {
            frame_type,
            time,
            frame,
            client_data: None,
            command: None,
            weapon_anim: None,
            sound: None,
        };

        let mut buffer_data: Option<Vec<u8>> = None;

        match frame_type {
            FrameType::NetMsgStart | FrameType::NetMsg => {
                // NetMsg frames contain the actual game data
                // Structure: DemoInfo (436 bytes) + SequenceInfo (28 bytes) + msg_len (4 bytes) + data
                // DemoInfo contains RefParams (vieworg, viewangles, etc), UserCmd, MoveVars
                //
                // RefParams layout (first 24 bytes):
                //   vieworg[3]: 3 floats (12 bytes) - camera position
                //   viewangles[3]: 3 floats (12 bytes) - camera angles
                // This is the spectator camera position in HLTV demos!

                // NetMsg DemoInfo structure (436 bytes for Protocol 47)
                // HLTV demos don't have valid camera positions in DemoInfo/RefParams
                // Skip the entire DemoInfo header
                self.skip_bytes(436)?;

                // Skip SequenceInfo (28 bytes = 7 × i32)
                self.skip_bytes(28)?;

                // Read message length
                let msg_len = self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?;

                // Read and store network message data if present
                if msg_len > 0 && msg_len < 100_000 {
                    let mut buf = vec![0u8; msg_len as usize];
                    self.data.read_exact(&mut buf).map_err(|e| e.to_string())?;
                    buffer_data = Some(buf);
                } else if msg_len > 0 {
                    // Skip oversized message
                    self.skip_bytes(msg_len as usize)?;
                }
            }
            FrameType::DemoStart | FrameType::NextSection => {}
            FrameType::ConsoleCommand => {
                demo_frame.command = Some(self.read_string(64)?);
            }
            FrameType::ClientData => {
                demo_frame.client_data = Some(ClientData {
                    origin: Vec3::new(
                        self.data
                            .read_f32::<LittleEndian>()
                            .map_err(|e| e.to_string())?,
                        self.data
                            .read_f32::<LittleEndian>()
                            .map_err(|e| e.to_string())?,
                        self.data
                            .read_f32::<LittleEndian>()
                            .map_err(|e| e.to_string())?,
                    ),
                    viewangles: Vec3::new(
                        self.data
                            .read_f32::<LittleEndian>()
                            .map_err(|e| e.to_string())?,
                        self.data
                            .read_f32::<LittleEndian>()
                            .map_err(|e| e.to_string())?,
                        self.data
                            .read_f32::<LittleEndian>()
                            .map_err(|e| e.to_string())?,
                    ),
                    weapon_bits: self
                        .data
                        .read_i32::<LittleEndian>()
                        .map_err(|e| e.to_string())?,
                    fov: self
                        .data
                        .read_f32::<LittleEndian>()
                        .map_err(|e| e.to_string())?,
                });
            }
            FrameType::Event => {
                // Skip event data: flags(4) + index(4) + delay(4) + EventArgs(72)
                self.skip_bytes(84)?;
            }
            FrameType::WeaponAnim => {
                let anim = self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?;
                let body = self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?;
                demo_frame.weapon_anim = Some((anim, body));
            }
            FrameType::Sound => {
                // channel is only meaningful to the original mixer.
                self.skip_bytes(4)?;
                let sample_len = self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?;
                if sample_len < 0 || sample_len > 4096 {
                    return Err(format!("invalid DEM_SOUND sample length {sample_len}"));
                }
                let mut sample_bytes = vec![0u8; sample_len as usize];
                self.data
                    .read_exact(&mut sample_bytes)
                    .map_err(|e| e.to_string())?;
                let attenuation = self
                    .data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?;
                let volume = self
                    .data
                    .read_f32::<LittleEndian>()
                    .map_err(|e| e.to_string())?;
                let _flags = self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?;
                let pitch = self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?;
                let end = sample_bytes
                    .iter()
                    .position(|byte| *byte == 0)
                    .unwrap_or(sample_bytes.len());
                let sample = String::from_utf8_lossy(&sample_bytes[..end]).replace('\\', "/");
                if !sample.is_empty() {
                    demo_frame.sound = Some(DemoSound {
                        time,
                        sample,
                        volume,
                        attenuation,
                        pitch,
                    });
                }
            }
            FrameType::DemoBuffer => {
                let length = self
                    .data
                    .read_i32::<LittleEndian>()
                    .map_err(|e| e.to_string())?;
                if length > 0 && length < 1_000_000 {
                    let mut buf = vec![0u8; length as usize];
                    self.data.read_exact(&mut buf).map_err(|e| e.to_string())?;
                    buffer_data = Some(buf);
                } else {
                    self.skip_bytes(length as usize)?;
                }
            }
            FrameType::Unknown => {
                // Unknown frame type - stop parsing this segment
                return Ok(None);
            }
        }

        Ok(Some((demo_frame, buffer_data)))
    }

    fn read_string(&mut self, max_len: usize) -> Result<String, String> {
        let mut bytes = vec![0u8; max_len];
        self.data
            .read_exact(&mut bytes)
            .map_err(|e| e.to_string())?;
        let s = String::from_utf8_lossy(&bytes);
        Ok(s.trim_end_matches('\0').to_string())
    }

    fn skip_bytes(&mut self, count: usize) -> Result<(), String> {
        self.data
            .seek(SeekFrom::Current(count as i64))
            .map_err(|e| e.to_string())?;
        Ok(())
    }
}

/// Scan raw data for death messages with position-based timestamp estimation
/// Estimate demo time for a raw file offset via (offset, frame-time) anchors,
/// falling back to a linear byte->time ratio when no anchors exist.
fn anchor_time(
    anchors: &[(u64, f32)],
    pos: usize,
    data_len: f32,
    duration: f32,
    time_map: &dyn Fn(f32) -> f32,
) -> f32 {
    if anchors.is_empty() {
        return (pos as f32 / data_len) * duration;
    }
    let p = pos as u64;
    let idx = anchors.partition_point(|(o, _)| *o <= p);
    let raw = if idx == 0 {
        anchors[0].1
    } else if idx >= anchors.len() {
        anchors[anchors.len() - 1].1
    } else {
        let (o0, t0) = anchors[idx - 1];
        let (o1, t1) = anchors[idx];
        if o1 > o0 {
            t0 + ((p - o0) as f32 / (o1 - o0) as f32) * (t1 - t0)
        } else {
            t0
        }
    };
    time_map(raw)
}

fn scan_for_death_messages_with_timestamps(
    data: &[u8],
    event_parser: &mut crate::events::EventParser,
    duration: f32,
    anchors: &[(u64, f32)],
    time_map: &dyn Fn(f32) -> f32,
) {
    use crate::types::{GameEvent, GameEventData, GameEventType};

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
    ];

    let data_len = data.len() as f32;
    let mut found_count = 0;

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
                        // Estimate timestamp based on position in file
                        let estimated_time = anchor_time(anchors, i, data_len, duration, time_map);

                        // 1-based entity indices -> 0-based registry slots
                        let killer_name = if killer_id > 0 {
                            event_parser.get_player_name(killer_id - 1)
                        } else {
                            None
                        };
                        let victim_name = event_parser.get_player_name(victim_id - 1);

                        // Check for duplicate (same victim, similar time)
                        let is_duplicate = event_parser.events.iter().any(|e| {
                            (e.time - estimated_time).abs() < 2.0
                                && e.data.victim == victim_name
                                && matches!(
                                    e.event_type,
                                    GameEventType::Kill | GameEventType::Suicide
                                )
                        });

                        if !is_duplicate {
                            let event_type = if killer_id == victim_id || killer_id == 0 {
                                GameEventType::Suicide
                            } else {
                                GameEventType::Kill
                            };

                            event_parser.events.push(GameEvent {
                                time: estimated_time,
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
                            found_count += 1;
                        }
                    }
                }
            }
        }
    }

    let _ = found_count; // Keep for potential debugging
}

/// Scan raw data for round end messages and estimate timestamps by file position
fn scan_for_round_end_messages_with_timestamps(
    data: &[u8],
    event_parser: &mut crate::events::EventParser,
    duration: f32,
    anchors: &[(u64, f32)],
    time_map: &dyn Fn(f32) -> f32,
) {
    use crate::types::{GameEvent, GameEventData, GameEventType};

    let patterns: [(&[u8], &str); 6] = [
        (b"Terrorists Win", "T"),
        (b"Counter-Terrorists Win", "CT"),
        (b"Terrorists_Win", "T"),
        (b"CTs_Win", "CT"),
        (b"Counter-Terrorists_Win", "CT"),
        (b"Round_Draw", "DRAW"),
    ];

    let data_len = data.len() as f32;
    let mut found_count = 0;

    for (pat, winner) in patterns.iter() {
        for i in 0..data.len().saturating_sub(pat.len() + 1) {
            if data[i..].starts_with(pat) {
                // Do not match the "Terrorists Win" suffix inside
                // "Counter-Terrorists Win" (and the equivalent localization
                // key). This previously emitted both T and CT wins for every
                // CT round.
                if i > 0 {
                    let before = data[i - 1];
                    if before.is_ascii_alphanumeric() || before == b'-' || before == b'_' {
                        continue;
                    }
                }
                // Require null terminator after string to reduce false positives
                let after = i + pat.len();
                if after < data.len() && data[after] != 0 {
                    continue;
                }

                let estimated_time = anchor_time(anchors, i, data_len, duration, time_map);

                // Avoid duplicates close in time for the same winner
                let is_duplicate = event_parser.events.iter().any(|e| {
                    (e.time - estimated_time).abs() < 5.0
                        && matches!(e.event_type, GameEventType::RoundEnd)
                        && e.data.winner.as_deref() == Some(*winner)
                });

                if !is_duplicate {
                    event_parser.events.push(GameEvent {
                        time: estimated_time,
                        event_type: GameEventType::RoundEnd,
                        data: GameEventData {
                            player: None,
                            model: None,
                            killer: None,
                            victim: None,
                            weapon: None,
                            headshot: false,
                            message: None,
                            winner: Some((*winner).to_string()),
                            team: None,
                            score: None,
                            round_time: None,
                        },
                    });
                    found_count += 1;
                }
            }
        }
    }

    let _ = found_count; // Keep for potential debugging
}

/// Replace sparse/duplicated round markers with one canonical live-round
/// start per round. Full RoundTime values are authoritative. POV demos often
/// omit them after signon, so missing starts are inferred from RoundEnd using
/// the median observed restart delay (20s is the CS competitive fallback:
/// five-second result display plus fifteen-second freeze time).
fn normalize_round_events(events: &mut Vec<GameEvent>, duration: f32) {
    use crate::types::{GameEventData, GameEventType};

    events.sort_by(|a, b| {
        a.time
            .partial_cmp(&b.time)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    // Round-result strings can arrive through both the parsed message stream
    // and the raw fallback scanner. Keep only one result in a five-second
    // window, regardless of which path found it.
    let mut last_end = f32::NEG_INFINITY;
    events.retain(|event| {
        if !matches!(event.event_type, GameEventType::RoundEnd) {
            return true;
        }
        if event.time - last_end < 5.0 {
            return false;
        }
        last_end = event.time;
        true
    });

    let round_ends: Vec<f32> = events
        .iter()
        .filter(|event| matches!(event.event_type, GameEventType::RoundEnd))
        .map(|event| event.time)
        .collect();
    let mut full_timers: Vec<f32> = events
        .iter()
        .filter(|event| {
            matches!(event.event_type, GameEventType::RoundTime)
                && event.data.round_time.unwrap_or(0) >= 100
        })
        .map(|event| event.time)
        .collect();
    full_timers.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    full_timers.dedup_by(|a, b| (*a - *b).abs() < 3.0);

    let mut observed_delays: Vec<f32> = Vec::new();
    for end in &round_ends {
        if let Some(start) = full_timers
            .iter()
            .find(|start| **start > *end + 3.0 && **start < *end + 35.0)
        {
            observed_delays.push(*start - *end);
        }
    }
    observed_delays.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let restart_delay = observed_delays
        .get(observed_delays.len() / 2)
        .copied()
        .unwrap_or(20.0)
        .clamp(6.0, 25.0);

    let mut starts = full_timers;
    for end in round_ends {
        let has_authoritative = starts
            .iter()
            .any(|start| *start > end + 3.0 && *start < end + 35.0);
        if !has_authoritative {
            let inferred = end + restart_delay;
            if inferred < duration - 1.0 {
                starts.push(inferred);
            }
        }
    }
    starts.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    starts.dedup_by(|a, b| (*a - *b).abs() < 10.0);

    // ResetHUD is recorder-local and often missing or repeated. Replace it
    // with the canonical live starts above.
    events.retain(|event| !matches!(event.event_type, GameEventType::RoundStart));
    for time in starts {
        events.push(GameEvent {
            time,
            event_type: GameEventType::RoundStart,
            data: GameEventData {
                killer: None,
                victim: None,
                weapon: None,
                headshot: false,
                message: Some("Round started".to_string()),
                winner: None,
                team: None,
                score: None,
                round_time: None,
                player: None,
                model: None,
            },
        });
    }
    events.sort_by(|a, b| {
        a.time
            .partial_cmp(&b.time)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
}

/// Scan demo data to find the actual duration by looking for time patterns
fn scan_for_duration(data: &[u8]) -> f32 {
    let mut max_time: f32 = 0.0;

    // Scan through data looking for valid frame patterns
    // Frame structure: type(1) + time(4) + frame_num(4)
    // We look for valid frame types followed by reasonable time values
    let mut i = 0;
    while i + 9 < data.len() {
        let frame_type = data[i];
        // Valid frame types are 2-9 (or 0-1 in some versions)
        if frame_type <= 9 {
            // Read potential time value (bytes i+1 to i+4)
            let time_bytes = [data[i + 1], data[i + 2], data[i + 3], data[i + 4]];
            let time = f32::from_le_bytes(time_bytes);

            // Check if time is reasonable (0 to 10000 seconds)
            if time.is_finite() && time >= 0.0 && time < 10000.0 {
                if time > max_time {
                    max_time = time;
                }
            }
        }
        i += 1;
    }

    max_time
}

/// Frame data with buffer for netcode parsing
struct FrameWithBuffer {
    time: f32,
    client_data: Option<ClientData>,
    buffer_data: Option<Vec<u8>>,
}

/// Build a timeline from parsed demo, sampled at fixed intervals
/// Uses entity parsing to extract player positions from network messages
pub fn build_timeline(demo: &ParsedDemo, sample_interval: f32, raw_data: &[u8]) -> Timeline {
    build_timeline_with_progress(demo, sample_interval, raw_data, None)
}

/// `progress` is called with a 0.0..=1.0 fraction as the buffer loop advances.
pub fn build_timeline_with_progress(
    demo: &ParsedDemo,
    sample_interval: f32,
    raw_data: &[u8],
    progress: Option<&dyn Fn(f32)>,
) -> Timeline {
    use crate::entity::EntityState;
    use crate::events::EventParser;

    let mut entries = Vec::new();
    let mut max_time: f32 = 0.0;

    // Fresh delta registry / HLTV detection state for this demo
    netmsg::reset_parser_state();

    // Event parser for game events (kills, rounds, etc.)
    let mut event_parser = EventParser::new();

    // Build player index -> name mapping
    for player in &demo.players {
        event_parser.register_player(player.index, player.name.clone());
    }

    // Scan raw data for user message definitions
    netmsg::scan_for_user_message_defs(raw_data, &mut event_parser);

    // Use already-parsed DemoBuffer frames, or scan raw data for HLTV demos
    let demo_buffers: Vec<(f32, Vec<u8>)> = if demo.demo_buffers.is_empty() {
        scan_for_network_data(raw_data, &demo.directory)
    } else {
        demo.demo_buffers.clone()
    };

    let mut entity_state = EntityState::new();
    let mut last_sample_time = -sample_interval;
    let mut obj_track: Vec<ObjSample> = Vec::new();

    // Build player slot -> name mapping for timeline
    let mut player_names: std::collections::HashMap<u8, String> = std::collections::HashMap::new();
    for player in &demo.players {
        player_names.insert(player.index, player.name.clone());
    }

    let mut total_player_updates = 0;
    let mut buffers_with_players = 0;
    let mut buffer_idx = 0;

    // Get demo duration from directory for time scaling
    let directory_duration = demo
        .directory
        .iter()
        .filter(|e| e.entry_type == 1)
        .map(|e| e.track_time)
        .fold(0.0f32, |a, b| a.max(b));

    // Find max buffer index (for rescaling sequential indices to real time)
    let max_buffer_idx = demo_buffers
        .iter()
        .map(|(t, _)| *t)
        .filter(|t| t.is_finite() && *t >= 0.0)
        .fold(1.0f32, |a, b| a.max(b));

    // If buffer "times" span roughly the directory duration, they are real
    // frame times (possibly offset by server uptime) — use them directly
    // instead of linearly rescaling sequential indices, which warps the time
    // axis and desyncs events from positions.
    let min_buffer_time = demo_buffers
        .iter()
        .map(|(t, _)| *t)
        .filter(|t| t.is_finite() && *t >= 0.0)
        .fold(f32::INFINITY, |a, b| a.min(b));
    let buffer_span = max_buffer_idx - min_buffer_time;
    let times_are_real = directory_duration > 0.0
        && buffer_span.is_finite()
        && buffer_span > 0.0
        && buffer_span / directory_duration > 0.7
        && buffer_span / directory_duration < 1.3;
    let map_time = |raw: f32| -> f32 {
        if times_are_real {
            raw - min_buffer_time
        } else if max_buffer_idx > 0.0 && directory_duration > 0.0 {
            (raw / max_buffer_idx) * directory_duration
        } else {
            raw
        }
    };
    if times_are_real {
        crate::console_log!(
            "Using real frame times (span {:.0}s, offset {:.0}s)",
            buffer_span,
            min_buffer_time
        );
    }

    crate::console_log!(
        "Processing {} demo buffers, duration={:.0}s, max_idx={:.0}",
        demo_buffers.len(),
        directory_duration,
        max_buffer_idx
    );

    // Pre-process the LOADING-segment signon stream so delta definitions,
    // ServerInfo, and baselines are registered before playback buffers.
    // Some demos (e.g. certain WCG POV recordings) carry these ONLY in the
    // LOADING segment; without this every ClientData message desyncs.
    if !demo.demo_buffers.is_empty() {
        event_parser.set_time(0.0);
        for chunk in loading_segment_chunks(raw_data, &demo.directory) {
            let _ = netmsg::parse_demo_buffer_with_events(
                &chunk,
                &mut entity_state,
                &mut event_parser,
                false,
            );
        }
    }

    let total_buffers = demo_buffers.len().max(1);
    for (loop_idx, (seq_idx, buffer_data)) in demo_buffers.iter().enumerate() {
        if let Some(cb) = progress {
            if loop_idx % 512 == 0 {
                cb(loop_idx as f32 / total_buffers as f32);
            }
        }
        // Map raw frame time (or sequential index) onto the demo time axis
        let time = map_time(*seq_idx);

        if !time.is_finite() || time < 0.0 {
            continue;
        }
        max_time = max_time.max(time);

        // Parse entity updates from this buffer
        entity_state.begin_frame();
        buffer_idx += 1;
        event_parser.set_time(time);
        // Debug first 3 buffers to see SVC parsing
        let debug_this = buffer_idx <= 3;
        let _ = netmsg::parse_demo_buffer_with_events(
            buffer_data,
            &mut entity_state,
            &mut event_parser,
            debug_this,
        );

        // Sample at intervals
        if time >= last_sample_time + sample_interval {
            // Non-player objects (grenades, planted C4) with known models
            for (ent, model_index, origin) in entity_state.get_object_positions() {
                let Some(name) = netmsg::model_name(model_index) else {
                    continue;
                };
                let kind = if name.contains("w_hegrenade") {
                    1
                } else if name.contains("w_flashbang") {
                    2
                } else if name.contains("w_smokegrenade") {
                    3
                } else if name.contains("w_c4") || name.ends_with("c4.mdl") {
                    4
                } else if name.contains("w_backpack") {
                    5 // dropped C4 (CS shows it as the backpack model)
                } else if let Some(pos) = name.find("w_") {
                    // Keep every stock CS 1.6 dropped weapon/equipment model
                    // distinct so the browser can render the exact pickup.
                    match &name[pos..name.len().min(pos + 18)] {
                        s if s.starts_with("w_ak47") => 10,
                        s if s.starts_with("w_m4a1") => 11,
                        s if s.starts_with("w_awp") => 12,
                        s if s.starts_with("w_deagle") => 13,
                        s if s.starts_with("w_mp5") => 14,
                        s if s.starts_with("w_usp") => 15,
                        s if s.starts_with("w_glock") => 16,
                        s if s.starts_with("w_famas") => 17,
                        s if s.starts_with("w_galil") => 18,
                        s if s.starts_with("w_sg552") => 19,
                        s if s.starts_with("w_aug") => 20,
                        s if s.starts_with("w_scout") => 21,
                        s if s.starts_with("w_elite") => 22,
                        s if s.starts_with("w_fiveseven") => 23,
                        s if s.starts_with("w_g3sg1") => 24,
                        s if s.starts_with("w_m249") => 25,
                        s if s.starts_with("w_m3") => 26,
                        s if s.starts_with("w_mac10") => 27,
                        s if s.starts_with("w_p228") => 28,
                        s if s.starts_with("w_p90") => 29,
                        s if s.starts_with("w_sg550") => 30,
                        s if s.starts_with("w_tmp") => 31,
                        s if s.starts_with("w_ump45") => 32,
                        s if s.starts_with("w_xm1014") => 33,
                        s if s.starts_with("w_knife") => 34,
                        s if s.starts_with("w_shield") => 35,
                        s if s.starts_with("w_assault") => 36,
                        s if s.starts_with("w_kevlar") => 37,
                        s if s.starts_with("w_thighpack") => 38,
                        _ => 0,
                    }
                } else {
                    0
                };
                if kind > 0 {
                    obj_track.push(ObjSample {
                        time,
                        ent,
                        kind,
                        origin,
                    });
                }
            }

            // Get all active player positions
            let player_positions = entity_state.get_player_positions();

            if !player_positions.is_empty() {
                buffers_with_players += 1;
                total_player_updates += player_positions.len();
                let players: Vec<PlayerState> = player_positions
                    .iter()
                    .map(
                        |(
                            slot,
                            origin,
                            angles,
                            velocity,
                            gait,
                            sequence,
                            frame,
                            effects,
                            ducking,
                            weapon,
                            health,
                        )| {
                            // Prefer the wire-accurate slot->name registry built from
                            // SVC_UpdateUserInfo; the scanned roster's indices are just
                            // discovery order and can point at the wrong entity.
                            let name = event_parser
                                .get_player_name(*slot)
                                .or_else(|| player_names.get(slot).cloned())
                                .unwrap_or_else(|| format!("Player {}", slot + 1));
                            PlayerState {
                                origin: origin.clone(),
                                angles: angles.clone(),
                                velocity: velocity.clone(),
                                name,
                                gait: *gait,
                                sequence: *sequence,
                                frame: *frame,
                                effects: *effects,
                                ducking: *ducking,
                                weapon: *weapon,
                                health: *health,
                            }
                        },
                    )
                    .collect();

                entries.push(TimelineEntry { time, players });
            }
            last_sample_time = time;
        }
    }

    crate::console_log!(
        "Timeline building: {} buffers processed, {} had players, {} entries created",
        buffer_idx,
        buffers_with_players,
        entries.len()
    );
    {
        let (msgs, with_ent, table) = netmsg::debug_event_stats();
        crate::console_log!(
            "Event stats: {} svc_event msgs, {} w/ entindex, {} eventscripts, {} shots",
            msgs,
            with_ent,
            table,
            event_parser.shots.len()
        );
    }

    // ClientData frames - for regular POV demos these have the camera position
    // For HLTV demos, these are typically all zeros (no local player)
    let client_data_positions: Vec<(f32, Vec3, Vec3, i32)> = demo
        .frames
        .iter()
        .filter_map(|frame| {
            frame.client_data.as_ref().map(|cd| {
                // Same time mapping as entity entries so both stay aligned
                (
                    map_time(frame.time),
                    cd.origin.clone(),
                    cd.viewangles.clone(),
                    cd.weapon_bits,
                )
            })
        })
        .filter(|(time, origin, _, _)| {
            // Validate position - must be non-zero and within bounds
            time.is_finite()
                && *time >= 0.0
                && *time < 10000.0
                && origin.x.is_finite()
                && origin.y.is_finite()
                && origin.z.is_finite()
                && origin.x.abs() < 5000.0
                && origin.y.abs() < 5000.0
                && origin.z.abs() < 2000.0
                && (origin.x.abs() > 10.0 || origin.y.abs() > 10.0 || origin.z.abs() > 10.0)
        })
        .collect();
    if !client_data_positions.is_empty() {
        crate::console_log!(
            "Found {} ClientData camera positions",
            client_data_positions.len()
        );
        // Log first few and last few positions to verify they change
        for (i, (time, origin, _, _)) in client_data_positions.iter().take(5).enumerate() {
            crate::console_log!(
                "  ClientData {}: time={:.2}, pos=({:.1}, {:.1}, {:.1})",
                i,
                time,
                origin.x,
                origin.y,
                origin.z
            );
        }
        if client_data_positions.len() > 10 {
            crate::console_log!("  ...");
            for (time, origin, _, _) in client_data_positions
                .iter()
                .rev()
                .take(3)
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
            {
                crate::console_log!(
                    "  ClientData (late): time={:.2}, pos=({:.1}, {:.1}, {:.1})",
                    time,
                    origin.x,
                    origin.y,
                    origin.z
                );
            }
        }

        // Add spectator camera to timeline entries, or use it as primary source
        if entries.is_empty() {
            crate::console_log!("Using ClientData for timeline (no entity positions)");
            last_sample_time = -sample_interval;

            for (time, origin, angles, _) in client_data_positions.iter() {
                if !time.is_finite() || *time < 0.0 || *time > 10000.0 {
                    continue;
                }
                max_time = max_time.max(*time);

                if *time >= last_sample_time + sample_interval {
                    entries.push(TimelineEntry {
                        time: *time,
                        players: vec![PlayerState {
                            origin: origin.clone(),
                            angles: angles.clone(),
                            velocity: Vec3::zero(),
                            name: "Spectator Camera".to_string(),
                            gait: 0,
                            sequence: 0,
                            frame: 0,
                            effects: 0,
                            ducking: false,
                            weapon: 0,
                            health: -1,
                        }],
                    });
                    last_sample_time = *time;
                }
            }
        } else {
            // Merge spectator camera with existing entity positions
            crate::console_log!(
                "Adding ClientData camera to existing {} entries",
                entries.len()
            );
            let mut cd_idx = 0;
            for entry in entries.iter_mut() {
                // Find closest ClientData position by time
                while cd_idx + 1 < client_data_positions.len()
                    && client_data_positions[cd_idx + 1].0 <= entry.time
                {
                    cd_idx += 1;
                }

                if cd_idx < client_data_positions.len() {
                    let (_, origin, angles, _) = &client_data_positions[cd_idx];
                    // Add spectator camera as another "player"
                    entry.players.push(PlayerState {
                        origin: origin.clone(),
                        angles: angles.clone(),
                        velocity: Vec3::zero(),
                        name: "Spectator Camera".to_string(),
                        gait: 0,
                        sequence: 0,
                        frame: 0,
                        effects: 0,
                        ducking: false,
                        weapon: 0,
                        health: -1,
                    });
                }
            }
        }
    }

    // Final fallback - use ClientData positions if no entity positions found
    if entries.is_empty() && !client_data_positions.is_empty() {
        crate::console_log!(
            "Using ClientData positions as final fallback ({} positions)",
            client_data_positions.len()
        );
        last_sample_time = -sample_interval;

        for (time, origin, angles, _) in client_data_positions.iter() {
            max_time = max_time.max(*time);

            if *time >= last_sample_time + sample_interval {
                entries.push(TimelineEntry {
                    time: *time,
                    players: vec![PlayerState {
                        origin: origin.clone(),
                        angles: angles.clone(),
                        velocity: Vec3::zero(),
                        name: "Spectator".to_string(),
                        gait: 0,
                        sequence: 0,
                        frame: 0,
                        effects: 0,
                        ducking: false,
                        weapon: 0,
                        health: -1,
                    }],
                });
                last_sample_time = *time;
            }
        }
    }

    // Get actual duration from directory entries (PLAYBACK segment)
    let directory_duration = demo
        .directory
        .iter()
        .filter(|e| e.entry_type == 1) // PLAYBACK segment
        .map(|e| e.track_time)
        .fold(0.0f32, |a, b| a.max(b));

    if directory_duration > max_time {
        max_time = directory_duration;
    }

    crate::console_log!(
        "Demo loaded: {} players, {} events, {:.0}s duration, {} timeline entries",
        demo.players.len(),
        event_parser.events.len(),
        max_time,
        entries.len()
    );

    // Scan entire raw data for death messages with position-based timestamps
    scan_for_death_messages_with_timestamps(
        raw_data,
        &mut event_parser,
        max_time,
        &demo.buffer_anchors,
        &map_time,
    );
    // Scan raw data for round end messages (fallback for missing user messages)
    scan_for_round_end_messages_with_timestamps(
        raw_data,
        &mut event_parser,
        max_time,
        &demo.buffer_anchors,
        &map_time,
    );

    // Sort by time
    entries.sort_by(|a, b| {
        a.time
            .partial_cmp(&b.time)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let mut events = event_parser.get_events();

    // Sort events by time
    events.sort_by(|a, b| {
        a.time
            .partial_cmp(&b.time)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    normalize_round_events(&mut events, max_time);

    // Rebuild the roster from the wire slot->name registry, keeping only
    // names that actually appear as entities, joined with the scanned
    // roster (and wire models) for team/model info.
    let entity_names: std::collections::HashSet<&str> = entries
        .iter()
        .flat_map(|e| e.players.iter().map(|p| p.name.as_str()))
        .collect();
    let mut regs: Vec<(u8, String)> = event_parser.player_names.clone();
    regs.sort_by_key(|(slot, _)| *slot);
    let mut wire_players: Vec<PlayerInfo> = Vec::new();
    for (slot, name) in regs {
        if !entity_names.contains(name.as_str()) {
            continue;
        }
        if wire_players.iter().any(|p| p.name == name) {
            continue;
        }
        let scanned = demo.players.iter().find(|s| s.name == name);
        wire_players.push(PlayerInfo {
            index: slot,
            name: name.clone(),
            team: scanned.map(|s| s.team.clone()).unwrap_or_default(),
            model: event_parser
                .get_player_model(slot)
                .or_else(|| scanned.map(|s| s.model.clone()))
                .unwrap_or_default(),
        });
    }

    let mut pov_track: Vec<PovSample> = client_data_positions
        .iter()
        .map(|(time, origin, angles, weapon_bits)| PovSample {
            time: *time,
            origin: origin.clone(),
            angles: angles.clone(),
            weapon_bits: *weapon_bits,
        })
        .collect();
    pov_track.sort_by(|a, b| {
        a.time
            .partial_cmp(&b.time)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    Timeline {
        entries,
        duration: max_time,
        events,
        wire_players,
        pov_track,
        obj_track,
        model_names: netmsg::all_model_names(),
        shot_track: {
            let mut s = event_parser.shots.clone();
            s.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
            s
        },
        hud_track: {
            let mut updates = event_parser.hud_updates.clone();
            updates.sort_by(|a, b| {
                a.time
                    .partial_cmp(&b.time)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            updates
        },
        hud_weapons: event_parser.hud_weapons.clone(),
        observer_track: {
            let mut updates = event_parser.observer_updates.clone();
            updates.sort_by(|a, b| {
                a.time
                    .partial_cmp(&b.time)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            updates.dedup_by(|a, b| {
                a.target == b.target && a.mode == b.mode && (a.time - b.time).abs() < 0.001
            });
            updates
        },
        weapon_anim_track: {
            let mut samples: Vec<WeaponAnimSample> = demo
                .frames
                .iter()
                .filter_map(|frame| {
                    frame.weapon_anim.map(|(sequence, body)| WeaponAnimSample {
                        time: frame.time,
                        sequence: sequence.clamp(0, u8::MAX as i32) as u8,
                        body: body.clamp(0, u8::MAX as i32) as u8,
                    })
                })
                .collect();
            samples.sort_by(|a, b| {
                a.time
                    .partial_cmp(&b.time)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            samples
                .dedup_by(|a, b| a.time == b.time && a.sequence == b.sequence && a.body == b.body);
            samples
        },
        sound_track: {
            let mut samples: Vec<DemoSound> = demo
                .frames
                .iter()
                .filter_map(|frame| frame.sound.clone())
                .collect();
            samples.sort_by(|a, b| {
                a.time
                    .partial_cmp(&b.time)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            samples
        },
        network_sound_track: {
            let mut samples = event_parser.network_sounds.clone();
            samples.sort_by(|a, b| {
                a.time
                    .partial_cmp(&b.time)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            samples
        },
        temp_effect_track: {
            let mut samples = event_parser.temp_effects.clone();
            samples.sort_by(|a, b| {
                a.time
                    .partial_cmp(&b.time)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            samples
        },
        player_stats_track: {
            let mut samples = event_parser.player_stats.clone();
            samples.sort_by(|a, b| {
                a.time
                    .partial_cmp(&b.time)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            samples
        },
    }
}

/// Scan for DemoBuffer frames with their timestamps
/// Returns: Vec<(time, buffer_data)>
fn scan_demo_buffer_frames(data: &[u8], directory: &[DirectoryEntry]) -> Vec<(f32, Vec<u8>)> {
    let mut results = Vec::new();

    // Protocol 47 frame types (offset by 2 from enum values):
    // 2 = DemoStart, 3 = ConsoleCommand, 4 = ClientData, 5 = NextSection
    // 6 = Event, 7 = WeaponAnim, 8 = Sound, 9 = DemoBuffer

    for entry in directory {
        if entry.entry_type != 1 {
            // PLAYBACK segment only
            continue;
        }

        let start = entry.offset as usize;
        let end = (entry.offset + entry.file_length) as usize;
        if end > data.len() {
            continue;
        }

        let segment = &data[start..end.min(data.len())];
        let mut i = 0;
        let mut frame_counts: [u32; 16] = [0; 16];
        let mut scanned = 0;
        let mut buffers_found = 0;

        while i + 9 < segment.len() {
            let frame_type = segment[i];
            if frame_type < 16 {
                frame_counts[frame_type as usize] += 1;
            }
            scanned += 1;
            if scanned >= 10000 {
                break;
            }

            // Read time and frame number (common to all frame types)
            let time = f32::from_le_bytes([
                segment[i + 1],
                segment[i + 2],
                segment[i + 3],
                segment[i + 4],
            ]);
            let _frame_num = i32::from_le_bytes([
                segment[i + 5],
                segment[i + 6],
                segment[i + 7],
                segment[i + 8],
            ]);

            match frame_type {
                2 | 5 => {
                    // DemoStart (2) or NextSection (5) - no extra data
                    i += 9;
                }
                3 => {
                    // ConsoleCommand - 64 bytes of command string
                    i += 9 + 64;
                }
                4 => {
                    // ClientData - 32 bytes of data
                    i += 9 + 32;
                }
                6 => {
                    // Event - 88 bytes
                    i += 9 + 88;
                }
                7 => {
                    // WeaponAnim - 8 bytes
                    i += 9 + 8;
                }
                8 => {
                    // Sound - variable length
                    if i + 13 >= segment.len() {
                        break;
                    }
                    let sample_len = i32::from_le_bytes([
                        segment[i + 9],
                        segment[i + 10],
                        segment[i + 11],
                        segment[i + 12],
                    ]);
                    if sample_len < 0 || sample_len > 1_000_000 {
                        break;
                    }
                    i += 9 + 4 + sample_len as usize + 16;
                }
                9 | 10 => {
                    // DemoBuffer (9) or extended DemoBuffer (10) - variable length
                    // Frame type 10 appears in some HLTV demos
                    if i + 13 >= segment.len() {
                        break;
                    }
                    let length = i32::from_le_bytes([
                        segment[i + 9],
                        segment[i + 10],
                        segment[i + 11],
                        segment[i + 12],
                    ]);
                    if length <= 0 || length > 10_000_000 {
                        i += 1;
                        continue;
                    }

                    let buf_start = i + 13;
                    let buf_end = buf_start + length as usize;

                    if buf_end <= segment.len() && time.is_finite() && time >= 0.0 {
                        // Include buffers with actual content (>50 bytes)
                        if length > 50 {
                            results.push((time, segment[buf_start..buf_end].to_vec()));
                            buffers_found += 1;
                        }
                    }

                    i = buf_end;
                }
                _ => {
                    // Unknown frame type - try to detect and skip
                    // Look for next valid frame type
                    let mut found = false;
                    for skip in 1..100 {
                        if i + skip + 9 >= segment.len() {
                            break;
                        }
                        let next_type = segment[i + skip];
                        if next_type >= 2 && next_type <= 10 {
                            // Looks like a valid frame type
                            let next_time = f32::from_le_bytes([
                                segment[i + skip + 1],
                                segment[i + skip + 2],
                                segment[i + skip + 3],
                                segment[i + skip + 4],
                            ]);
                            // Valid if time is reasonable
                            if next_time.is_finite() && next_time >= 0.0 && next_time <= time + 10.0
                            {
                                i += skip;
                                found = true;
                                break;
                            }
                        }
                    }
                    if !found {
                        i += 1;
                    }
                }
            }

            if i >= segment.len() {
                break;
            }
        }
        // frame_counts is unused but kept for potential debugging
        let _ = frame_counts;
    }

    // Sort by time
    results.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    results
}

/// Extract spectator camera positions from NetMsg frame DemoInfo headers
/// Returns: Vec<(time, origin_x, origin_y, origin_z)>
fn extract_refparams_positions(
    data: &[u8],
    directory: &[DirectoryEntry],
) -> Vec<(f32, f32, f32, f32)> {
    let mut positions = Vec::new();
    let mut debug_count = 0;

    for entry in directory {
        if entry.entry_type != 1 {
            // PLAYBACK segment
            continue;
        }

        let start = entry.offset as usize;
        let end = (entry.offset + entry.file_length) as usize;
        if end > data.len() {
            continue;
        }

        let segment = &data[start..end.min(data.len())];
        let mut i = 0;

        // Parse frames sequentially to avoid false positives
        while i + 500 < segment.len() {
            let frame_type = segment[i];
            let time = f32::from_le_bytes([
                segment[i + 1],
                segment[i + 2],
                segment[i + 3],
                segment[i + 4],
            ]);

            // Validate this looks like a real frame (time must be reasonable)
            if !time.is_finite() || time < 0.0 || time > 10000.0 {
                i += 1;
                continue;
            }

            match frame_type {
                // NetMsg frames (types 0 and 1) contain DemoInfo with RefParams
                0 | 1 => {
                    // Debug: dump first few NetMsg frames - search for valid position data
                    if debug_count < 1 {
                        debug_count += 1;
                        crate::console_log!(
                            "NetMsg {}: time={:.2}, raw bytes 9-60:",
                            debug_count,
                            time
                        );
                        let hex_bytes: Vec<String> = segment[i + 9..i + 60.min(segment.len())]
                            .iter()
                            .map(|b| format!("{:02x}", b))
                            .collect();
                        crate::console_log!("  {}", hex_bytes.join(" "));

                        // Scan larger range with more relaxed criteria
                        let mut found_any = false;
                        for base_offset in (9..500).step_by(4) {
                            let offs = i + base_offset;
                            if offs + 12 >= segment.len() {
                                break;
                            }

                            let vx = f32::from_le_bytes([
                                segment[offs],
                                segment[offs + 1],
                                segment[offs + 2],
                                segment[offs + 3],
                            ]);
                            let vy = f32::from_le_bytes([
                                segment[offs + 4],
                                segment[offs + 5],
                                segment[offs + 6],
                                segment[offs + 7],
                            ]);
                            let vz = f32::from_le_bytes([
                                segment[offs + 8],
                                segment[offs + 9],
                                segment[offs + 10],
                                segment[offs + 11],
                            ]);

                            // Look for valid CS map coordinates (relaxed - any non-zero)
                            if vx.is_finite()
                                && vy.is_finite()
                                && vz.is_finite()
                                && vx.abs() < 10000.0
                                && vy.abs() < 10000.0
                                && vz.abs() < 5000.0
                                && (vx.abs() > 100.0 || vy.abs() > 100.0)
                                && vz.abs() > 10.0
                                && vz.abs() < 500.0
                            {
                                if !found_any {
                                    crate::console_log!("  Potential positions found:");
                                    found_any = true;
                                }
                                crate::console_log!(
                                    "    offset +{}: ({:.1}, {:.1}, {:.1})",
                                    base_offset,
                                    vx,
                                    vy,
                                    vz
                                );
                            }
                        }
                        if !found_any {
                            crate::console_log!("  No valid positions found in first 500 bytes");
                        }
                    }

                    // Read vieworg from DemoInfo (at offset 9 after frame header)
                    let vieworg_offset = i + 9;
                    if vieworg_offset + 12 < segment.len() {
                        let x = f32::from_le_bytes([
                            segment[vieworg_offset],
                            segment[vieworg_offset + 1],
                            segment[vieworg_offset + 2],
                            segment[vieworg_offset + 3],
                        ]);
                        let y = f32::from_le_bytes([
                            segment[vieworg_offset + 4],
                            segment[vieworg_offset + 5],
                            segment[vieworg_offset + 6],
                            segment[vieworg_offset + 7],
                        ]);
                        let z = f32::from_le_bytes([
                            segment[vieworg_offset + 8],
                            segment[vieworg_offset + 9],
                            segment[vieworg_offset + 10],
                            segment[vieworg_offset + 11],
                        ]);

                        // Validate position is reasonable
                        if x.is_finite()
                            && y.is_finite()
                            && z.is_finite()
                            && x.abs() < 10000.0
                            && y.abs() < 10000.0
                            && z.abs() < 5000.0
                            && (x.abs() > 10.0 || y.abs() > 10.0 || z.abs() > 10.0)
                        {
                            positions.push((time, x, y, z));
                        }
                    }

                    // Calculate actual frame size and skip to next
                    // DemoInfo (436) + SequenceInfo (28) + msg_len (4) + msg_data
                    let msg_len_offset = i + 9 + 436 + 28;
                    if msg_len_offset + 4 < segment.len() {
                        let msg_len = u32::from_le_bytes([
                            segment[msg_len_offset],
                            segment[msg_len_offset + 1],
                            segment[msg_len_offset + 2],
                            segment[msg_len_offset + 3],
                        ]) as usize;
                        if msg_len < 100000 {
                            i = msg_len_offset + 4 + msg_len;
                            continue;
                        }
                    }
                    i += 500; // Fallback skip
                }
                2 | 5 => i += 9,  // DemoStart / NextSection
                3 => i += 9 + 64, // ConsoleCommand
                4 => i += 9 + 32, // ClientData
                6 => i += 9 + 88, // Event
                7 => i += 9 + 8,  // WeaponAnim
                8 => {
                    // Sound
                    if i + 13 < segment.len() {
                        let len = i32::from_le_bytes([
                            segment[i + 9],
                            segment[i + 10],
                            segment[i + 11],
                            segment[i + 12],
                        ]);
                        if len > 0 && len < 1_000_000 {
                            i += 9 + 4 + len as usize + 16;
                        } else {
                            i += 9;
                        }
                    } else {
                        i += 9;
                    }
                }
                9 => {
                    // DemoBuffer
                    if i + 13 < segment.len() {
                        let len = i32::from_le_bytes([
                            segment[i + 9],
                            segment[i + 10],
                            segment[i + 11],
                            segment[i + 12],
                        ]);
                        if len > 0 && len < 1_000_000 {
                            i += 13 + len as usize;
                        } else {
                            i += 9;
                        }
                    } else {
                        i += 9;
                    }
                }
                _ => i += 1,
            }
        }
    }

    positions
}

/// Scan raw demo data for network message chunks
/// HLTV demos embed network data differently than POV demos
/// Extract the raw SVC signon stream(s) from LOADING segments (type 0).
/// These carry SVC_DELTADESCRIPTION / ServerInfo / baselines that the
/// playback buffers depend on.
fn loading_segment_chunks(data: &[u8], directory: &[DirectoryEntry]) -> Vec<Vec<u8>> {
    let mut chunks = Vec::new();
    for entry in directory {
        if entry.entry_type != 0 {
            continue;
        }

        let start = entry.offset as usize;
        let end = (entry.offset + entry.file_length) as usize;
        if end > data.len() {
            continue;
        }

        let segment = &data[start..end];

        // Find SVC_PRINT (8) followed by readable ASCII as the start of SVC stream
        for i in 0..segment.len().saturating_sub(50) {
            if segment[i] == 8 {
                // SVC_PRINT
                // Verify it's followed by printable ASCII
                let mut text_len = 0;
                for j in i + 1..segment.len().min(i + 200) {
                    if segment[j] == 0 {
                        break;
                    }
                    if segment[j] >= 32 && segment[j] < 127 {
                        text_len += 1;
                    } else {
                        break;
                    }
                }
                if text_len > 10 {
                    chunks.push(segment[i..].to_vec());
                    break;
                }
            }
        }
    }
    chunks
}

fn scan_for_network_data(data: &[u8], directory: &[DirectoryEntry]) -> Vec<(f32, Vec<u8>)> {
    let mut results = Vec::new();

    // Strategy 1: Extract SVC data from LOADING segment (type 0)
    for chunk in loading_segment_chunks(data, directory) {
        results.push((0.0, chunk));
    }

    // Strategy 2: Look for DemoBuffer frames (type 9) in PLAYBACK segment
    for entry in directory {
        if entry.entry_type != 1 {
            continue;
        }

        let start = entry.offset as usize;
        let end = (entry.offset + entry.file_length) as usize;
        if end > data.len() {
            continue;
        }

        let segment = &data[start..end];
        crate::console_log!(
            "PLAYBACK segment: offset={}, len={}, first 32 bytes: {:02x?}",
            start,
            segment.len(),
            &segment[..32.min(segment.len())]
        );

        let mut i = 0;
        let mut last_time: f32 = 0.0;
        let mut demo_buffer_count = 0;
        let mut frame_type_counts: [u32; 16] = [0; 16];

        // HLTV demos use frame types 0 and 1 for network data, not type 9
        // Frame structure: type(1) + time(4) + frame(4) + [type-specific data]
        while i + 9 < segment.len() {
            let frame_type = segment[i];
            if (frame_type as usize) < 16 {
                frame_type_counts[frame_type as usize] += 1;
            }

            let time = f32::from_le_bytes([
                segment[i + 1],
                segment[i + 2],
                segment[i + 3],
                segment[i + 4],
            ]);

            // Track last valid time for progress
            if time.is_finite() && time >= 0.0 && time <= 50000.0 && time >= last_time {
                last_time = time;
            }

            match frame_type {
                // NetMsg frames (types 0 and 1) - these contain the actual network messages
                // Structure: type(1) + time(4) + frame(4) + DemoInfo(~400 bytes) + SequenceInfo(28) + msg_len(4) + data
                // DemoInfo contains: RefParams, UserCmd, MoveVars, view data
                0 | 1 => {
                    // NetMsg frame has a LARGE header before the message data
                    // Approximate sizes based on GoldSrc SDK:
                    // - RefParams: ~76 floats/ints ≈ 304 bytes
                    // - UserCmd: ~16 fields ≈ 52 bytes
                    // - MoveVars: ~22 fields ≈ 100 bytes
                    // - View/viewmodel: ~20 fields ≈ 80 bytes
                    // - SequenceInfo: 7 × i32 = 28 bytes
                    // Total header after frame header: ~464 bytes + 28 + 4 = ~496 bytes

                    // The message_length field is at a large offset
                    // Let's scan for it by looking for a reasonable length value followed by valid SVC data
                    let frame_time = f32::from_le_bytes([
                        segment[i + 1],
                        segment[i + 2],
                        segment[i + 3],
                        segment[i + 4],
                    ]);

                    let mut found_data = false;

                    // Try different header sizes
                    // Protocol 47: DemoInfo (436 bytes) + SequenceInfo (28 bytes) = 464 bytes
                    // But some sources say DemoInfo is 436, so total offset to msg_len is 436+28 = 464
                    for header_size in [436u32, 464, 468, 440, 444, 448, 452, 456, 460].iter() {
                        let len_pos = i + 9 + *header_size as usize; // 9 = frame header
                        if len_pos + 4 >= segment.len() {
                            continue;
                        }

                        let msg_length = u32::from_le_bytes([
                            segment[len_pos],
                            segment[len_pos + 1],
                            segment[len_pos + 2],
                            segment[len_pos + 3],
                        ]);

                        // Valid message length and check first byte looks like SVC message
                        if msg_length > 20 && msg_length < 65536 {
                            let data_start = len_pos + 4;
                            let data_end = data_start + msg_length as usize;

                            if data_end <= segment.len() {
                                let first_svc = segment[data_start];
                                // Check if first byte could be a valid SVC type (1-58)
                                if first_svc > 0 && first_svc <= 58 {
                                    let sequential_time = demo_buffer_count as f32;

                                    if demo_buffer_count < 3 {
                                        crate::console_log!("  NetMsg frame: header_size={}, msg_len={}, first_svc={}, time={:.2}",
                                            header_size, msg_length, first_svc, frame_time);
                                    }
                                    results.push((
                                        sequential_time,
                                        segment[data_start..data_end].to_vec(),
                                    ));
                                    demo_buffer_count += 1;
                                    i = data_end;
                                    found_data = true;
                                    break;
                                }
                            }
                        }
                    }

                    if !found_data {
                        i += 9; // Skip frame header and continue
                    }
                }
                2 | 5 => i += 9,  // DemoStart / NextSection
                3 => i += 9 + 64, // ConsoleCommand
                4 => i += 9 + 32, // ClientData
                6 => i += 9 + 88, // Event
                7 => i += 9 + 8,  // WeaponAnim
                8 => {
                    // Sound frame
                    if i + 13 < segment.len() {
                        let sample_len = i32::from_le_bytes([
                            segment[i + 9],
                            segment[i + 10],
                            segment[i + 11],
                            segment[i + 12],
                        ]);
                        if sample_len >= 0 && sample_len < 1_000_000 {
                            i += 9 + 4 + sample_len as usize + 16;
                        } else {
                            i += 9;
                        }
                    } else {
                        i += 9;
                    }
                }
                9 => {
                    // DemoBuffer frame (POV demos)
                    if i + 13 < segment.len() {
                        let length = i32::from_le_bytes([
                            segment[i + 9],
                            segment[i + 10],
                            segment[i + 11],
                            segment[i + 12],
                        ]);
                        if length > 20 && length < 100_000 && time.is_finite() && time >= 0.0 {
                            let buf_start = i + 13;
                            let buf_end = buf_start + length as usize;
                            if buf_end <= segment.len() {
                                results.push((time, segment[buf_start..buf_end].to_vec()));
                                demo_buffer_count += 1;
                                i = buf_end;
                                continue;
                            }
                        }
                        if length > 0 && length < 10_000_000 {
                            i += 13 + length as usize;
                        } else {
                            i += 9;
                        }
                    } else {
                        i += 9;
                    }
                }
                _ => {
                    // Unknown frame type - skip 1 byte and rescan
                    i += 1;
                }
            }

            // Safety limit
            if frame_type_counts.iter().sum::<u32>() > 100000 {
                break;
            }
        }

        crate::console_log!(
            "  Frame types: 0={}, 1={}, 2={}, 3={}, 4={}, 5={}, 9={}, extracted={}",
            frame_type_counts[0],
            frame_type_counts[1],
            frame_type_counts[2],
            frame_type_counts[3],
            frame_type_counts[4],
            frame_type_counts[5],
            frame_type_counts[9],
            demo_buffer_count
        );
    }

    if !results.is_empty() {
        results.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
        return results;
    }
    results
}

/// Scan for ClientData frames directly in raw data
/// Returns: Vec<(time, origin, angles)>
fn scan_for_client_data_frames(
    data: &[u8],
    directory: &[DirectoryEntry],
) -> Vec<(f32, Vec3, Vec3)> {
    let mut results = Vec::new();

    // ClientData frame format (Protocol 47):
    // type(1) = 4 + time(4) + frame_num(4) + origin(12) + viewangles(12) + weapon_bits(4) + fov(4)
    // Total header: 9 bytes, data: 32 bytes

    for entry in directory {
        if entry.entry_type != 1 {
            // PLAYBACK segment only
            continue;
        }

        let start = entry.offset as usize;
        let end = (entry.offset + entry.file_length) as usize;
        if end > data.len() {
            continue;
        }

        let segment = &data[start..end.min(data.len())];
        let mut i = 0;

        while i + 41 < segment.len() {
            // 9 header + 32 data
            let frame_type = segment[i];

            // ClientData is type 4 in protocol 47
            if frame_type == 4 {
                let time = f32::from_le_bytes([
                    segment[i + 1],
                    segment[i + 2],
                    segment[i + 3],
                    segment[i + 4],
                ]);
                let _frame_num = i32::from_le_bytes([
                    segment[i + 5],
                    segment[i + 6],
                    segment[i + 7],
                    segment[i + 8],
                ]);

                // Validate time
                if time.is_finite() && time >= 0.0 && time < 10000.0 {
                    // Read origin (3 floats)
                    let origin_x = f32::from_le_bytes([
                        segment[i + 9],
                        segment[i + 10],
                        segment[i + 11],
                        segment[i + 12],
                    ]);
                    let origin_y = f32::from_le_bytes([
                        segment[i + 13],
                        segment[i + 14],
                        segment[i + 15],
                        segment[i + 16],
                    ]);
                    let origin_z = f32::from_le_bytes([
                        segment[i + 17],
                        segment[i + 18],
                        segment[i + 19],
                        segment[i + 20],
                    ]);

                    // Read viewangles (3 floats)
                    let angles_x = f32::from_le_bytes([
                        segment[i + 21],
                        segment[i + 22],
                        segment[i + 23],
                        segment[i + 24],
                    ]);
                    let angles_y = f32::from_le_bytes([
                        segment[i + 25],
                        segment[i + 26],
                        segment[i + 27],
                        segment[i + 28],
                    ]);
                    let angles_z = f32::from_le_bytes([
                        segment[i + 29],
                        segment[i + 30],
                        segment[i + 31],
                        segment[i + 32],
                    ]);

                    // Validate position - must be non-zero and within reasonable bounds
                    let has_valid_pos = origin_x.is_finite()
                        && origin_y.is_finite()
                        && origin_z.is_finite()
                        && angles_x.is_finite()
                        && angles_y.is_finite()
                        && angles_z.is_finite()
                        && origin_x.abs() < 5000.0
                        && origin_y.abs() < 5000.0
                        && origin_z.abs() < 2000.0
                        && (origin_x.abs() > 10.0
                            || origin_y.abs() > 10.0
                            || origin_z.abs() > 10.0); // Not at origin

                    if has_valid_pos {
                        results.push((
                            time,
                            Vec3::new(origin_x, origin_y, origin_z),
                            Vec3::new(angles_x, angles_y, angles_z),
                        ));
                    }

                    i += 41; // Skip this frame
                    continue;
                }
            }

            i += 1;
        }
    }

    // Sort by time
    results.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    results
}

/// Scan raw demo data for large DemoBuffer frames that might contain entity data
/// This bypasses frame-by-frame parsing issues with type 0/1 frames
fn scan_for_large_buffers(data: &[u8], directory: &[DirectoryEntry]) -> Vec<(f32, Vec<u8>)> {
    let mut buffers = Vec::new();

    // Scan BOTH LOADING (type 0) and PLAYBACK (type 1) segments
    for entry in directory {
        if entry.entry_type != 0 && entry.entry_type != 1 {
            continue;
        }

        let start = entry.offset as usize;
        let end = (entry.offset + entry.file_length) as usize;
        if end > data.len() {
            continue;
        }

        let segment = &data[start..end.min(data.len())];

        // Scan for pattern: 09 <time:4> <frame:4> <length:4> where length > 50
        let mut i = 0;
        while i + 20 < segment.len() {
            if segment[i] == 9 {
                // Potential DemoBuffer frame
                let time_bytes = [
                    segment[i + 1],
                    segment[i + 2],
                    segment[i + 3],
                    segment[i + 4],
                ];
                let time = f32::from_le_bytes(time_bytes);

                let frame_bytes = [
                    segment[i + 5],
                    segment[i + 6],
                    segment[i + 7],
                    segment[i + 8],
                ];
                let frame = i32::from_le_bytes(frame_bytes);

                let len_bytes = [
                    segment[i + 9],
                    segment[i + 10],
                    segment[i + 11],
                    segment[i + 12],
                ];
                let length = i32::from_le_bytes(len_bytes);

                // Validate values (more lenient for LOADING segment)
                let valid_time = (entry.entry_type == 0 && time >= 0.0 && time <= 1.0)
                    || (entry.entry_type == 1 && time >= 0.0 && time <= 10000.0);
                let valid_frame = frame >= 0 && frame < 10000000;
                let valid_len =
                    length > 50 && length < 500000 && i + 13 + length as usize <= segment.len();

                if valid_time && valid_frame && valid_len {
                    let buf_start = i + 13;
                    let buf_end = buf_start + length as usize;
                    let buffer = segment[buf_start..buf_end].to_vec();

                    // Accept buffers that have any valid SVC message
                    let first_byte = buffer.get(0).copied().unwrap_or(0);
                    let is_svc_start = first_byte <= 58; // Valid SVC range
                    let has_svc_inside = buffer
                        .iter()
                        .any(|&b| b == 22 || b == 40 || b == 41 || b == 39);

                    if is_svc_start || has_svc_inside {
                        buffers.push((time, buffer));
                    }

                    i = buf_end;
                    continue;
                }
            }
            i += 1;
        }
    }

    buffers
}

/// Re-parse frames from raw data to get buffer data for netcode parsing
fn parse_frames_for_timeline(raw_data: &[u8], demo: &ParsedDemo) -> Vec<FrameWithBuffer> {
    let mut frames = Vec::new();
    let mut cursor = Cursor::new(raw_data);

    // Skip header (544 bytes)
    if cursor.seek(SeekFrom::Start(544)).is_err() {
        return frames;
    }

    // Parse frames from each directory entry
    for entry in &demo.directory {
        if entry.entry_type != 0 && entry.entry_type != 1 {
            continue;
        }

        if cursor.seek(SeekFrom::Start(entry.offset as u64)).is_err() {
            continue;
        }

        let end_offset = entry.offset as u64 + entry.file_length as u64;

        while cursor.position() < end_offset {
            // Frame type (1 byte)
            let frame_type_raw = match cursor.read_u8() {
                Ok(v) => v,
                Err(_) => break,
            };

            // Time (4 bytes)
            let time = match cursor.read_f32::<LittleEndian>() {
                Ok(v) => v,
                Err(_) => break,
            };

            // Frame number (4 bytes)
            let _ = cursor.read_i32::<LittleEndian>();

            let frame_type = FrameType::from(frame_type_raw as i32);

            let mut frame = FrameWithBuffer {
                time,
                client_data: None,
                buffer_data: None,
            };

            match frame_type {
                FrameType::NetMsgStart | FrameType::NetMsg => {
                    // Read vieworg from RefParams (first 24 bytes of DemoInfo)
                    let vieworg_x = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);
                    let vieworg_y = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);
                    let vieworg_z = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);
                    let viewangles_x = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);
                    let viewangles_y = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);
                    let viewangles_z = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);

                    if vieworg_x.is_finite() && vieworg_y.is_finite() && vieworg_z.is_finite() {
                        frame.client_data = Some(ClientData {
                            origin: Vec3::new(vieworg_x, vieworg_y, vieworg_z),
                            viewangles: Vec3::new(viewangles_x, viewangles_y, viewangles_z),
                            weapon_bits: 0,
                            fov: 90.0,
                        });
                    }

                    // Skip rest of DemoInfo (436 - 24 = 412 bytes) + SequenceInfo (28 bytes)
                    let _ = cursor.seek(SeekFrom::Current(440));

                    // Read message length
                    let msg_len = cursor.read_i32::<LittleEndian>().unwrap_or(0);

                    if msg_len > 0 && msg_len < 100_000 {
                        let mut buf = vec![0u8; msg_len as usize];
                        if cursor.read_exact(&mut buf).is_ok() {
                            frame.buffer_data = Some(buf);
                        }
                    } else if msg_len > 0 {
                        let _ = cursor.seek(SeekFrom::Current(msg_len as i64));
                    }
                }
                FrameType::DemoStart | FrameType::NextSection => {}
                FrameType::ConsoleCommand => {
                    // Skip 64 bytes
                    let _ = cursor.seek(SeekFrom::Current(64));
                }
                FrameType::ClientData => {
                    // Read origin (3 floats) + angles (3 floats) + weapon_bits (4) + fov (4)
                    let origin_x = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);
                    let origin_y = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);
                    let origin_z = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);
                    let angles_x = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);
                    let angles_y = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);
                    let angles_z = cursor.read_f32::<LittleEndian>().unwrap_or(0.0);
                    let weapon_bits = cursor.read_i32::<LittleEndian>().unwrap_or(0);
                    let fov = cursor.read_f32::<LittleEndian>().unwrap_or(90.0);

                    frame.client_data = Some(ClientData {
                        origin: Vec3::new(origin_x, origin_y, origin_z),
                        viewangles: Vec3::new(angles_x, angles_y, angles_z),
                        weapon_bits,
                        fov,
                    });
                }
                FrameType::Event => {
                    // Skip 88 bytes
                    let _ = cursor.seek(SeekFrom::Current(88));
                }
                FrameType::WeaponAnim => {
                    // Skip 8 bytes
                    let _ = cursor.seek(SeekFrom::Current(8));
                }
                FrameType::Sound => {
                    // Skip 4 bytes (channel)
                    let _ = cursor.seek(SeekFrom::Current(4));
                    let sample_len = cursor.read_i32::<LittleEndian>().unwrap_or(0);
                    // Skip sample + 16 bytes
                    let _ = cursor.seek(SeekFrom::Current(sample_len as i64 + 16));
                }
                FrameType::DemoBuffer => {
                    let length = cursor.read_i32::<LittleEndian>().unwrap_or(0);
                    if length > 0 && length < 1_000_000 {
                        let mut buf = vec![0u8; length as usize];
                        if cursor.read_exact(&mut buf).is_ok() {
                            frame.buffer_data = Some(buf);
                        }
                    } else {
                        let _ = cursor.seek(SeekFrom::Current(length as i64));
                    }
                }
                FrameType::Unknown => {
                    break;
                }
            }

            if frame_type == FrameType::NextSection {
                break;
            }

            frames.push(frame);

            // Safety limit
            if frames.len() > 100000 {
                break;
            }
        }
    }

    frames
}
