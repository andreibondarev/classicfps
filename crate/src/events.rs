/// Game event parsing for CS 1.6 demos
///
/// CS 1.6 uses user messages to communicate game events like kills, round changes, etc.
/// These messages are defined by SVC_NEWUSERMSG and sent with custom message IDs.
use crate::types::{
    GameEvent, GameEventData, GameEventType, HudUpdate, HudWeaponDef, NetworkSound, ObserverSample,
    PlayerStatsUpdate, TempEffect,
};

/// Known CS 1.6 user message types
/// Message IDs are assigned dynamically, but we track them by name
#[derive(Debug, Clone)]
pub struct UserMessageDef {
    pub id: u8,
    pub name: String,
    pub size: i8, // -1 for variable length
}

/// Tracks user message definitions and parsed events
#[derive(Debug, Default)]
pub struct EventParser {
    /// User message definitions (id -> name mapping)
    pub user_messages: Vec<UserMessageDef>,
    /// Parsed game events
    pub events: Vec<GameEvent>,
    /// Player names by index (for resolving killer/victim)
    pub player_names: Vec<(u8, String)>,
    /// Player models by index (from wire userinfo, for roster building)
    pub player_models: Vec<(u8, String)>,
    /// Current time for events
    pub current_time: f32,
    /// Weapon-fire events: (time, 0-based shooter slot)
    pub shots: Vec<(f32, u8)>,
    /// Recorder-local HUD state changes.
    pub hud_updates: Vec<HudUpdate>,
    /// WeaponList definitions (weapon id -> primary ammo id/name).
    pub hud_weapons: Vec<HudWeaponDef>,
    pub observer_updates: Vec<ObserverSample>,
    pub observer_target: u16,
    pub observer_mode: u8,
    pub network_sounds: Vec<NetworkSound>,
    pub temp_effects: Vec<TempEffect>,
    pub player_stats: Vec<PlayerStatsUpdate>,
}

impl EventParser {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a user message definition from SVC_NEWUSERMSG
    pub fn register_user_message(&mut self, id: u8, name: String, size: i8) {
        self.user_messages.push(UserMessageDef { id, name, size });
    }

    /// Set current time for subsequent events
    pub fn set_time(&mut self, time: f32) {
        self.current_time = time;
    }

    /// Register a player name for index resolution
    pub fn register_player(&mut self, index: u8, name: String) {
        // Remove old entry if exists
        self.player_names.retain(|(i, _)| *i != index);
        self.player_names.push((index, name));
    }

    /// Get player name by index
    pub fn get_player_name(&self, index: u8) -> Option<String> {
        self.player_names
            .iter()
            .find(|(i, _)| *i == index)
            .map(|(_, name)| name.clone())
    }

    /// Register a player model (from wire userinfo) for roster building
    pub fn register_player_model(&mut self, index: u8, model: String) {
        self.player_models.retain(|(i, _)| *i != index);
        self.player_models.push((index, model));
    }

    /// Get player model by index
    pub fn get_player_model(&self, index: u8) -> Option<String> {
        self.player_models
            .iter()
            .find(|(i, _)| *i == index)
            .map(|(_, model)| model.clone())
    }

    /// Get message name by ID
    pub fn get_message_name(&self, id: u8) -> Option<&str> {
        self.user_messages
            .iter()
            .find(|m| m.id == id)
            .map(|m| m.name.as_str())
    }

    /// Get message size by ID (-1 for variable length)
    pub fn get_message_size(&self, id: u8) -> Option<i8> {
        self.user_messages
            .iter()
            .find(|m| m.id == id)
            .map(|m| m.size)
    }

    /// Parse a user message and extract game events
    pub fn parse_user_message(&mut self, msg_id: u8, data: &[u8]) {
        let msg_name = match self.get_message_name(msg_id) {
            Some(name) => name.to_string(),
            None => return, // Unknown message type
        };

        match msg_name.as_str() {
            "DeathMsg" => self.parse_death_msg(data),
            "TextMsg" => self.parse_text_msg(data),
            "SayText" => self.parse_say_text(data),
            "SendAudio" => self.parse_send_audio(data),
            "ResetHUD" => self.parse_reset_hud(),
            "RoundTime" => self.parse_round_time(data),
            "ScoreInfo" => self.parse_score_info(data),
            "ScoreAttrib" => self.parse_score_attrib(data),
            "TeamInfo" => self.parse_team_info(data),
            "TeamScore" => self.parse_team_score(data),
            "Health" => self.push_hud_byte(1, data),
            "Battery" => self.parse_battery(data),
            "Money" => self.parse_money(data),
            "CurWeapon" => self.parse_cur_weapon(data),
            "AmmoX" => self.parse_ammo(data),
            "HideWeapon" => self.push_hud_byte(6, data),
            "SetFOV" => self.push_hud_byte(7, data),
            "ScreenFade" => self.parse_screen_fade(data),
            "BarTime" => self.parse_bar_time(data, false),
            "BarTime2" => self.parse_bar_time(data, true),
            "WeaponList" => self.parse_weapon_list(data),
            _ => { /* Other messages we don't care about */ }
        }
    }

    fn push_hud(&mut self, kind: u8, a: i32, b: i32) {
        self.hud_updates.push(HudUpdate {
            time: self.current_time,
            kind,
            a,
            b,
        });
    }

    pub fn set_observer_target(&mut self, target: u16) {
        self.observer_target = target;
        self.push_observer();
    }

    pub fn set_observer_mode(&mut self, mode: u8) {
        self.observer_mode = mode;
        self.push_observer();
    }

    fn push_observer(&mut self) {
        let sample = ObserverSample {
            time: self.current_time,
            target: self.observer_target,
            mode: self.observer_mode,
        };
        if self.observer_updates.last().is_some_and(|previous| {
            previous.target == sample.target
                && previous.mode == sample.mode
                && (previous.time - sample.time).abs() < 0.001
        }) {
            return;
        }
        self.observer_updates.push(sample);
    }

    fn push_hud_byte(&mut self, kind: u8, data: &[u8]) {
        if let Some(value) = data.first() {
            self.push_hud(kind, *value as i32, 0);
        }
    }

    fn parse_battery(&mut self, data: &[u8]) {
        let value = if data.len() >= 2 {
            i16::from_le_bytes([data[0], data[1]]) as i32
        } else if let Some(value) = data.first() {
            *value as i32
        } else {
            return;
        };
        self.push_hud(2, value.clamp(0, 999), 0);
    }

    fn parse_money(&mut self, data: &[u8]) {
        if data.len() < 4 {
            return;
        }
        let amount = i32::from_le_bytes([data[0], data[1], data[2], data[3]]);
        self.push_hud(3, amount, data.get(4).copied().unwrap_or(0) as i32);
    }

    fn parse_cur_weapon(&mut self, data: &[u8]) {
        if data.len() < 3 || data[0] == 0 {
            return;
        }
        let clip = if data[2] == u8::MAX {
            -1
        } else {
            data[2] as i32
        };
        self.push_hud(4, data[1] as i32, clip);
    }

    fn parse_ammo(&mut self, data: &[u8]) {
        if data.len() < 2 {
            return;
        }
        self.push_hud(5, data[0] as i32, data[1] as i32);
    }

    fn parse_screen_fade(&mut self, data: &[u8]) {
        if data.len() < 10 {
            return;
        }
        let duration = u16::from_le_bytes([data[0], data[1]]) as u32;
        let hold = u16::from_le_bytes([data[2], data[3]]) as u32;
        let flags = u16::from_le_bytes([data[4], data[5]]) as i32;
        let timing = (duration | (hold << 16)) as i32;
        let rgba = (data[6] as u32)
            | ((data[7] as u32) << 8)
            | ((data[8] as u32) << 16)
            | ((data[9] as u32) << 24);
        self.push_hud(9, timing, rgba as i32);
        self.push_hud(10, flags, 0);
    }

    fn parse_bar_time(&mut self, data: &[u8], with_start_percent: bool) {
        if data.len() < 2 {
            return;
        }
        let duration = i16::from_le_bytes([data[0], data[1]]) as i32;
        let start_percent = if with_start_percent && data.len() >= 4 {
            i16::from_le_bytes([data[2], data[3]]) as i32
        } else {
            0
        };
        self.push_hud(11, duration.max(0), start_percent.clamp(0, 100));
    }

    /// WeaponList: name\0, ammo1 id/max, ammo2 id/max, slot, position,
    /// weapon id, flags. Signed -1 ammo ids arrive as 255.
    fn parse_weapon_list(&mut self, data: &[u8]) {
        let Some(nul) = data.iter().position(|&byte| byte == 0) else {
            return;
        };
        if data.len() < nul + 9 {
            return;
        }
        let tail = &data[nul + 1..];
        let name = String::from_utf8_lossy(&data[..nul])
            .trim_start_matches("weapon_")
            .to_string();
        let ammo_id = tail[0] as i8;
        let id = tail[6];
        if id == 0 || name.is_empty() {
            return;
        }
        self.hud_weapons.retain(|weapon| weapon.id != id);
        self.hud_weapons.push(HudWeaponDef { id, ammo_id, name });
    }

    fn parse_score_info(&mut self, data: &[u8]) {
        if data.len() < 5 || data[0] == 0 {
            return;
        }
        self.player_stats.push(PlayerStatsUpdate {
            time: self.current_time,
            slot: data[0] - 1,
            frags: Some(i16::from_le_bytes([data[1], data[2]])),
            deaths: Some(i16::from_le_bytes([data[3], data[4]])),
            team: None,
            flags: None,
        });
    }

    fn parse_score_attrib(&mut self, data: &[u8]) {
        if data.len() < 2 || data[0] == 0 {
            return;
        }
        self.player_stats.push(PlayerStatsUpdate {
            time: self.current_time,
            slot: data[0] - 1,
            frags: None,
            deaths: None,
            team: None,
            flags: Some(data[1]),
        });
    }

    fn parse_team_info(&mut self, data: &[u8]) {
        if data.len() < 2 || data[0] == 0 {
            return;
        }
        let end = data[1..]
            .iter()
            .position(|byte| *byte == 0)
            .map(|offset| offset + 1)
            .unwrap_or(data.len());
        let team = String::from_utf8_lossy(&data[1..end]).trim().to_string();
        if team.is_empty() {
            return;
        }
        self.player_stats.push(PlayerStatsUpdate {
            time: self.current_time,
            slot: data[0] - 1,
            frags: None,
            deaths: None,
            team: Some(team),
            flags: None,
        });
    }

    /// Parse DeathMsg - player kill notification
    /// Format: killer_id(1) + victim_id(1) + headshot(1) + weapon_name(string)
    fn parse_death_msg(&mut self, data: &[u8]) {
        if data.len() < 3 {
            return;
        }

        let killer_id = data[0];
        let victim_id = data[1];
        let headshot = data[2] != 0;

        // Weapon name is null-terminated string starting at byte 3
        let weapon = if data.len() > 3 {
            let weapon_bytes: Vec<u8> =
                data[3..].iter().take_while(|&&b| b != 0).copied().collect();
            String::from_utf8_lossy(&weapon_bytes).to_string()
        } else {
            "unknown".to_string()
        };

        // DeathMsg IDs are 1-based entity indices; the name registry is keyed
        // by 0-based client slot (entity index - 1). 0 = world/no killer.
        let killer_name = if killer_id > 0 {
            self.get_player_name(killer_id - 1)
        } else {
            None
        };
        let victim_name = if victim_id > 0 {
            self.get_player_name(victim_id - 1)
        } else {
            None
        };

        // Determine event type
        let event_type = if killer_id == victim_id || killer_id == 0 {
            GameEventType::Suicide
        } else {
            GameEventType::Kill
        };

        self.events.push(GameEvent {
            time: self.current_time,
            event_type,
            data: GameEventData {
                player: None,
                model: None,
                killer: killer_name,
                victim: victim_name,
                weapon: Some(weapon),
                headshot,
                message: None,
                winner: None,
                team: None,
                score: None,
                round_time: None,
            },
        });
    }

    /// Parse TextMsg - game text messages
    /// Format: dest(1) + message_string(s)
    /// SayText: player chat. Format: sender entity index (1 byte), then
    /// null-terminated strings — either a preformatted line or a localization
    /// template ("#Cstrike_Chat_All") followed by name and text parameters.
    fn parse_say_text(&mut self, data: &[u8]) {
        if data.len() < 2 {
            return;
        }
        let sender = data[0];
        let mut strings: Vec<String> = Vec::new();
        let mut i = 1;
        while i < data.len() && strings.len() < 4 {
            let end = data[i..]
                .iter()
                .position(|&b| b == 0)
                .map(|p| i + p)
                .unwrap_or(data.len());
            if end > i {
                let s = String::from_utf8_lossy(&data[i..end]).trim().to_string();
                if !s.is_empty() {
                    strings.push(s);
                }
            }
            i = end + 1;
        }
        if strings.is_empty() {
            return;
        }

        let name = if sender > 0 {
            self.get_player_name(sender - 1)
        } else {
            None
        };
        let message = if strings[0].starts_with('#') {
            // Localized template: parameters follow (name, text)
            let team_tag = if strings[0].contains("_CT") {
                "(CT) "
            } else if strings[0].contains("_T") && !strings[0].contains("All") {
                "(T) "
            } else {
                ""
            };
            let text = strings.last().cloned().unwrap_or_default();
            let who = name
                .clone()
                .or_else(|| strings.get(1).cloned())
                .unwrap_or_else(|| "?".to_string());
            format!("{team_tag}{who}: {text}")
        } else {
            strings.join(" ")
        };

        // Strip GoldSrc color/control codes
        let message: String = message.chars().filter(|c| !c.is_control()).collect();
        if message.len() < 2 {
            return;
        }

        self.events.push(GameEvent {
            time: self.current_time,
            event_type: GameEventType::TextMessage,
            data: GameEventData {
                player: name,
                model: None,
                killer: None,
                victim: None,
                weapon: None,
                headshot: false,
                message: Some(message),
                winner: None,
                team: None,
                score: None,
                round_time: None,
            },
        });
    }

    fn parse_text_msg(&mut self, data: &[u8]) {
        if data.is_empty() {
            return;
        }

        let _dest = data[0]; // 1=console, 2=chat, 3=center, 4=radio

        // Message is null-terminated string(s) starting at byte 1
        let msg_bytes: Vec<u8> = data[1..].iter().take_while(|&&b| b != 0).copied().collect();
        let message = String::from_utf8_lossy(&msg_bytes).to_string();

        // Check for round-end localization/literal messages. Counter-
        // Terrorists must be tested first: its text contains the shorter
        // "Terrorists Win" suffix.
        let winner = if message.contains("Counter-Terrorists Win")
            || message.contains("#CTs_Win")
            || message.contains("#Target_Saved")
            || message.contains("#Bomb_Defused")
        {
            Some("CT")
        } else if message.contains("Terrorists Win")
            || message.contains("#Terrorists_Win")
            || message.contains("#Target_Bombed")
        {
            Some("T")
        } else {
            None
        };
        if let Some(winner) = winner {
            // Localized objective messages also end the round, but preserve
            // the specific bomb event so replay consumers can reconstruct
            // planting/defusing state and action timing.
            if message.contains("#Bomb_Defused") {
                self.events.push(GameEvent {
                    time: self.current_time,
                    event_type: GameEventType::BombDefused,
                    data: GameEventData {
                        player: None,
                        model: None,
                        killer: None,
                        victim: None,
                        weapon: None,
                        headshot: false,
                        message: Some(message.clone()),
                        winner: Some("CT".to_string()),
                        team: None,
                        score: None,
                        round_time: None,
                    },
                });
            } else if message.contains("#Target_Bombed") {
                self.events.push(GameEvent {
                    time: self.current_time,
                    event_type: GameEventType::BombExploded,
                    data: GameEventData {
                        player: None,
                        model: None,
                        killer: None,
                        victim: None,
                        weapon: None,
                        headshot: false,
                        message: Some(message.clone()),
                        winner: Some("T".to_string()),
                        team: None,
                        score: None,
                        round_time: None,
                    },
                });
            }
            self.events.push(GameEvent {
                time: self.current_time,
                event_type: GameEventType::RoundEnd,
                data: GameEventData {
                    player: None,
                    model: None,
                    killer: None,
                    victim: None,
                    weapon: None,
                    headshot: false,
                    message: Some(message.clone()),
                    winner: Some(winner.to_string()),
                    team: None,
                    score: None,
                    round_time: None,
                },
            });
        } else if message.contains("Target Bombed") {
            self.events.push(GameEvent {
                time: self.current_time,
                event_type: GameEventType::BombExploded,
                data: GameEventData {
                    player: None,
                    model: None,
                    killer: None,
                    victim: None,
                    weapon: None,
                    headshot: false,
                    message: Some(message),
                    winner: Some("T".to_string()),
                    team: None,
                    score: None,
                    round_time: None,
                },
            });
        } else if message.contains("Bomb has been defused") {
            self.events.push(GameEvent {
                time: self.current_time,
                event_type: GameEventType::BombDefused,
                data: GameEventData {
                    player: None,
                    model: None,
                    killer: None,
                    victim: None,
                    weapon: None,
                    headshot: false,
                    message: Some(message),
                    winner: Some("CT".to_string()),
                    team: None,
                    score: None,
                    round_time: None,
                },
            });
        } else if message.contains("planted the bomb") {
            self.events.push(GameEvent {
                time: self.current_time,
                event_type: GameEventType::BombPlanted,
                data: GameEventData {
                    player: None,
                    model: None,
                    killer: None,
                    victim: None,
                    weapon: None,
                    headshot: false,
                    message: Some(message),
                    winner: None,
                    team: None,
                    score: None,
                    round_time: None,
                },
            });
        } else if !message.is_empty() {
            // Handle common translation keys (messages starting with #)
            if message.starts_with('#') {
                if message.contains("Terrorists_Win") || message.contains("Ts_Win") {
                    self.events.push(GameEvent {
                        time: self.current_time,
                        event_type: GameEventType::RoundEnd,
                        data: GameEventData {
                            player: None,
                            model: None,
                            killer: None,
                            victim: None,
                            weapon: None,
                            headshot: false,
                            message: Some(message.clone()),
                            winner: Some("T".to_string()),
                            team: None,
                            score: None,
                            round_time: None,
                        },
                    });
                    return;
                }
                if message.contains("CTs_Win") || message.contains("Counter-Terrorists_Win") {
                    self.events.push(GameEvent {
                        time: self.current_time,
                        event_type: GameEventType::RoundEnd,
                        data: GameEventData {
                            player: None,
                            model: None,
                            killer: None,
                            victim: None,
                            weapon: None,
                            headshot: false,
                            message: Some(message.clone()),
                            winner: Some("CT".to_string()),
                            team: None,
                            score: None,
                            round_time: None,
                        },
                    });
                    return;
                }
                if message.contains("Round_Draw") {
                    self.events.push(GameEvent {
                        time: self.current_time,
                        event_type: GameEventType::RoundEnd,
                        data: GameEventData {
                            player: None,
                            model: None,
                            killer: None,
                            victim: None,
                            weapon: None,
                            headshot: false,
                            message: Some(message.clone()),
                            winner: Some("DRAW".to_string()),
                            team: None,
                            score: None,
                            round_time: None,
                        },
                    });
                    return;
                }
                if message.contains("Bomb_Defused") || message.contains("Bomb_Defused") {
                    self.events.push(GameEvent {
                        time: self.current_time,
                        event_type: GameEventType::BombDefused,
                        data: GameEventData {
                            player: None,
                            model: None,
                            killer: None,
                            victim: None,
                            weapon: None,
                            headshot: false,
                            message: Some(message.clone()),
                            winner: Some("CT".to_string()),
                            team: None,
                            score: None,
                            round_time: None,
                        },
                    });
                    return;
                }
                if message.contains("Target_Bombed") || message.contains("Bomb_Exploded") {
                    self.events.push(GameEvent {
                        time: self.current_time,
                        event_type: GameEventType::BombExploded,
                        data: GameEventData {
                            player: None,
                            model: None,
                            killer: None,
                            victim: None,
                            weapon: None,
                            headshot: false,
                            message: Some(message.clone()),
                            winner: Some("T".to_string()),
                            team: None,
                            score: None,
                            round_time: None,
                        },
                    });
                    return;
                }
                if message.contains("Bomb_Planted") {
                    self.events.push(GameEvent {
                        time: self.current_time,
                        event_type: GameEventType::BombPlanted,
                        data: GameEventData {
                            player: None,
                            model: None,
                            killer: None,
                            victim: None,
                            weapon: None,
                            headshot: false,
                            message: Some(message.clone()),
                            winner: None,
                            team: None,
                            score: None,
                            round_time: None,
                        },
                    });
                    return;
                }
            }

            // Generic text message
            self.events.push(GameEvent {
                time: self.current_time,
                event_type: GameEventType::TextMessage,
                data: GameEventData {
                    player: None,
                    model: None,
                    killer: None,
                    victim: None,
                    weapon: None,
                    headshot: false,
                    message: Some(message),
                    winner: None,
                    team: None,
                    score: None,
                    round_time: None,
                },
            });
        }
    }

    /// Parse SendAudio - radio commands
    fn parse_send_audio(&mut self, data: &[u8]) {
        if data.len() < 2 {
            return;
        }

        // Format: player_id(1) + audio_code(string)
        let _player_id = data[0];
        let audio_bytes: Vec<u8> = data[1..].iter().take_while(|&&b| b != 0).copied().collect();
        let audio_code = String::from_utf8_lossy(&audio_bytes).to_string();

        // Could parse radio commands like "%!MRAD_FIREINHOLE" etc.
        // For now, skip unless it's interesting
        if audio_code.contains("BOMBPL") {
            self.events.push(GameEvent {
                time: self.current_time,
                event_type: GameEventType::BombPlanted,
                data: GameEventData {
                    player: None,
                    model: None,
                    killer: None,
                    victim: None,
                    weapon: None,
                    headshot: false,
                    message: Some("Bomb has been planted".to_string()),
                    winner: None,
                    team: None,
                    score: None,
                    round_time: None,
                },
            });
        }
    }

    /// Parse ResetHUD - indicates round start
    fn parse_reset_hud(&mut self) {
        self.push_hud(8, 0, 0);
        self.events.push(GameEvent {
            time: self.current_time,
            event_type: GameEventType::RoundStart,
            data: GameEventData {
                player: None,
                model: None,
                killer: None,
                victim: None,
                weapon: None,
                headshot: false,
                message: Some("Round started".to_string()),
                winner: None,
                team: None,
                score: None,
                round_time: None,
            },
        });
    }

    /// Parse RoundTime - round timer update
    fn parse_round_time(&mut self, _data: &[u8]) {
        if _data.len() < 2 {
            return;
        }
        let secs = i16::from_le_bytes([_data[0], _data[1]]) as i32;
        if secs < 0 || secs > 3600 {
            return;
        }
        crate::console_log!("RoundTime: {}s at t={:.2}", secs, self.current_time);
        self.events.push(GameEvent {
            time: self.current_time,
            event_type: GameEventType::RoundTime,
            data: GameEventData {
                player: None,
                model: None,
                killer: None,
                victim: None,
                weapon: None,
                headshot: false,
                message: None,
                winner: None,
                team: None,
                score: None,
                round_time: Some(secs),
            },
        });
    }

    /// Parse TeamScore - team name and score update
    /// Format: team_name(string) + score(short)
    fn parse_team_score(&mut self, data: &[u8]) {
        if data.is_empty() {
            return;
        }

        let nul = match data.iter().position(|&b| b == 0) {
            Some(i) => i,
            None => return,
        };

        let team = String::from_utf8_lossy(&data[..nul]).to_string();
        // Counter-Strike's TeamScore wire values are canonical identifiers,
        // not arbitrary display strings. Reject control-byte payloads created
        // by a malformed/desynchronized user-message candidate.
        if !matches!(team.as_str(), "CT" | "TERRORIST" | "T") {
            return;
        }

        if data.len() < nul + 3 {
            return;
        }

        let score = i16::from_le_bytes([data[nul + 1], data[nul + 2]]) as i32;
        if score < 0 || score > 99 {
            return;
        }

        crate::console_log!(
            "TeamScore: {}={} at t={:.2}",
            team,
            score,
            self.current_time
        );
        self.events.push(GameEvent {
            time: self.current_time,
            event_type: GameEventType::TeamScore,
            data: GameEventData {
                player: None,
                model: None,
                killer: None,
                victim: None,
                weapon: None,
                headshot: false,
                message: None,
                winner: None,
                team: Some(team),
                score: Some(score),
                round_time: None,
            },
        });
    }

    /// Get all parsed events
    pub fn get_events(&self) -> Vec<GameEvent> {
        self.events.clone()
    }

    /// Format an event for display
    pub fn format_event(event: &GameEvent) -> String {
        match event.event_type {
            GameEventType::Kill => {
                let killer = event.data.killer.as_deref().unwrap_or("???");
                let victim = event.data.victim.as_deref().unwrap_or("???");
                let weapon = event.data.weapon.as_deref().unwrap_or("???");
                let hs = if event.data.headshot {
                    " (headshot)"
                } else {
                    ""
                };
                format!(
                    "[{:.1}s] {} killed {} with {}{}",
                    event.time, killer, victim, weapon, hs
                )
            }
            GameEventType::Suicide => {
                let victim = event.data.victim.as_deref().unwrap_or("???");
                format!("[{:.1}s] {} died", event.time, victim)
            }
            GameEventType::RoundStart => {
                format!("[{:.1}s] === Round Started ===", event.time)
            }
            GameEventType::RoundEnd => {
                let winner = event.data.winner.as_deref().unwrap_or("???");
                format!("[{:.1}s] === {} Wins ===", event.time, winner)
            }
            GameEventType::TeamScore => {
                let team = event.data.team.as_deref().unwrap_or("???");
                let score = event.data.score.unwrap_or(0);
                format!("[{:.1}s] {} score = {}", event.time, team, score)
            }
            GameEventType::RoundTime => {
                let secs = event.data.round_time.unwrap_or(0);
                format!("[{:.1}s] Round time: {}s", event.time, secs)
            }
            GameEventType::BombPlanted => {
                format!("[{:.1}s] ** BOMB PLANTED **", event.time)
            }
            GameEventType::BombDefused => {
                format!("[{:.1}s] ** BOMB DEFUSED **", event.time)
            }
            GameEventType::BombExploded => {
                format!("[{:.1}s] ** BOMB EXPLODED **", event.time)
            }
            GameEventType::TextMessage => {
                let msg = event.data.message.as_deref().unwrap_or("");
                format!("[{:.1}s] {}", event.time, msg)
            }
            _ => format!("[{:.1}s] {:?}", event.time, event.event_type),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::EventParser;
    use crate::types::GameEventType;

    #[test]
    fn parses_authoritative_hud_messages() {
        let mut parser = EventParser::new();
        for (id, name, size) in [
            (64, "Health", 1),
            (65, "Battery", 2),
            (66, "Money", 5),
            (67, "CurWeapon", 3),
            (68, "AmmoX", 2),
            (69, "SetFOV", 1),
            (70, "ScreenFade", 10),
            (71, "BarTime", 2),
            (72, "BarTime2", 4),
        ] {
            parser.register_user_message(id, name.to_string(), size);
        }
        parser.set_time(12.5);
        parser.parse_user_message(64, &[73]);
        parser.parse_user_message(65, &85i16.to_le_bytes());
        parser.parse_user_message(66, &[0x10, 0x0e, 0, 0, 1]);
        parser.parse_user_message(67, &[1, 28, 24]);
        parser.parse_user_message(68, &[4, 61]);
        parser.parse_user_message(69, &[40]);
        parser.parse_user_message(70, &[0x00, 0x10, 0x00, 0x08, 0x02, 0, 255, 250, 240, 220]);
        parser.parse_user_message(71, &5i16.to_le_bytes());
        parser.parse_user_message(72, &[10, 0, 25, 0]);

        let values: Vec<(u8, i32, i32)> = parser
            .hud_updates
            .iter()
            .map(|update| (update.kind, update.a, update.b))
            .collect();
        assert_eq!(
            values,
            vec![
                (1, 73, 0),
                (2, 85, 0),
                (3, 3600, 1),
                (4, 28, 24),
                (5, 4, 61),
                (7, 40, 0),
                (9, 0x08001000, -588_186_881),
                (10, 2, 0),
                (11, 5, 0),
                (11, 10, 25),
            ]
        );
        assert!(parser.hud_updates.iter().all(|update| update.time == 12.5));
    }

    #[test]
    fn parses_weapon_list_ammo_definition() {
        let mut parser = EventParser::new();
        parser.register_user_message(70, "WeaponList".to_string(), -1);
        let mut data = b"weapon_ak47\0".to_vec();
        data.extend_from_slice(&[4, 90, 255, 255, 0, 1, 28, 0]);
        parser.parse_user_message(70, &data);

        assert_eq!(parser.hud_weapons.len(), 1);
        assert_eq!(parser.hud_weapons[0].id, 28);
        assert_eq!(parser.hud_weapons[0].ammo_id, 4);
        assert_eq!(parser.hud_weapons[0].name, "ak47");
    }

    #[test]
    fn counter_terrorist_win_is_not_misclassified_as_terrorist_win() {
        let mut parser = EventParser::new();
        parser.register_user_message(71, "TextMsg".to_string(), -1);
        let mut data = vec![3];
        data.extend_from_slice(b"Counter-Terrorists Win\0");
        parser.parse_user_message(71, &data);

        assert_eq!(parser.events.len(), 1);
        assert_eq!(parser.events[0].data.winner.as_deref(), Some("CT"));
    }

    #[test]
    fn localized_defuse_preserves_objective_and_round_end_events() {
        let mut parser = EventParser::new();
        parser.register_user_message(71, "TextMsg".to_string(), -1);
        parser.parse_user_message(71, b"\x03#Bomb_Defused\0");

        assert_eq!(parser.events.len(), 2);
        assert!(matches!(
            parser.events[0].event_type,
            GameEventType::BombDefused
        ));
        assert!(matches!(
            parser.events[1].event_type,
            GameEventType::RoundEnd
        ));
        assert_eq!(parser.events[1].data.winner.as_deref(), Some("CT"));
    }

    #[test]
    fn parses_scoreboard_team_and_attribute_updates() {
        let mut parser = EventParser::new();
        parser.register_user_message(72, "ScoreInfo".to_string(), 9);
        parser.register_user_message(73, "ScoreAttrib".to_string(), 2);
        parser.register_user_message(74, "TeamInfo".to_string(), -1);
        parser.set_time(42.25);

        parser.parse_user_message(72, &[3, 7, 0, 4, 0, 0, 0, 0, 0]);
        parser.parse_user_message(73, &[3, 3]);
        parser.parse_user_message(74, b"\x03CT\0");

        assert_eq!(parser.player_stats.len(), 3);
        assert_eq!(parser.player_stats[0].slot, 2);
        assert_eq!(parser.player_stats[0].frags, Some(7));
        assert_eq!(parser.player_stats[0].deaths, Some(4));
        assert_eq!(parser.player_stats[1].flags, Some(3));
        assert_eq!(parser.player_stats[2].team.as_deref(), Some("CT"));
        assert!(parser
            .player_stats
            .iter()
            .all(|update| update.time == 42.25));
    }
}
