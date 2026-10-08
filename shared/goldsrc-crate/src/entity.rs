use crate::delta::EntityDelta;
/// Entity state management for GoldSrc demos
///
/// Entities are the core objects in the GoldSrc engine. Players are entities
/// with indices 1-32 (index 0 is the world entity).
use crate::types::Vec3;
use std::collections::HashMap;

/// Maximum number of entities in GoldSrc
pub const MAX_ENTITIES: usize = 1024;

/// Maximum players in a game
pub const MAX_PLAYERS: usize = 32;

/// A single entity's state
#[derive(Clone, Debug)]
pub struct Entity {
    pub index: u16,
    pub origin: Vec3,
    pub angles: Vec3,
    pub velocity: Vec3,
    pub model_index: u16,
    pub frame: u8,
    pub skin: u8,
    pub effects: u32,
    pub solid: u8,
    pub sequence: u8,
    pub gaitsequence: u8,
    pub weapon_model: u16,
    pub health: i16,
    pub ducking: bool,
    pub active: bool,
}

impl Entity {
    pub fn new(index: u16) -> Self {
        Self {
            index,
            origin: Vec3::zero(),
            angles: Vec3::zero(),
            velocity: Vec3::zero(),
            model_index: 0,
            frame: 0,
            skin: 0,
            effects: 0,
            solid: 0,
            sequence: 0,
            gaitsequence: 0,
            weapon_model: 0,
            health: -1,
            ducking: false,
            active: false,
        }
    }

    /// Check if this entity is a player (indices 1-32)
    pub fn is_player(&self) -> bool {
        self.index >= 1 && self.index <= MAX_PLAYERS as u16
    }

    /// Get player slot (0-based) if this is a player entity
    pub fn player_slot(&self) -> Option<u8> {
        if self.is_player() {
            Some((self.index - 1) as u8)
        } else {
            None
        }
    }
}

impl Default for Entity {
    fn default() -> Self {
        Self::new(0)
    }
}

/// Manages entity state for the entire game
#[derive(Debug)]
pub struct EntityState {
    /// Current state of all entities
    pub entities: HashMap<u16, Entity>,
    /// Baseline states (initial states from SVC_SPAWNBASELINE)
    pub baselines: HashMap<u16, Entity>,
    /// Instance baselines (for additional entities)
    pub instance_baselines: HashMap<u16, Entity>,
    /// Player slot to entity index mapping (from SVC_UPDATEUSERINFO)
    pub player_entities: [u16; MAX_PLAYERS],
    /// Track which entities have been updated this frame
    updated_this_frame: Vec<u16>,
    /// Actual server max players (from SVC_SERVERINFO); entities above this
    /// index are world entities, not players.
    pub max_players: u16,
}

impl EntityState {
    pub fn new() -> Self {
        Self {
            entities: HashMap::new(),
            baselines: HashMap::new(),
            instance_baselines: HashMap::new(),
            player_entities: [0; MAX_PLAYERS],
            updated_this_frame: Vec::new(),
            max_players: MAX_PLAYERS as u16,
        }
    }

    /// Set the real max player count (from SVC_SERVERINFO)
    pub fn set_max_players(&mut self, n: u16) {
        if n >= 1 && n <= MAX_PLAYERS as u16 {
            self.max_players = n;
        }
    }

    /// Set baseline state for an entity (from SVC_SPAWNBASELINE)
    pub fn set_baseline(&mut self, index: u16, entity: Entity) {
        self.baselines.insert(index, entity);
    }

    /// Set instance baseline for an entity
    pub fn set_instance_baseline(&mut self, index: u16, entity: Entity) {
        self.instance_baselines.insert(index, entity);
    }

    /// Get or create entity at index, using baseline if available
    pub fn get_or_create(&mut self, index: u16) -> &mut Entity {
        if !self.entities.contains_key(&index) {
            // Start from baseline if available
            let entity = if let Some(baseline) = self.baselines.get(&index) {
                let mut e = baseline.clone();
                e.active = true;
                e
            } else if let Some(baseline) = self.instance_baselines.get(&index) {
                let mut e = baseline.clone();
                e.active = true;
                e
            } else {
                let mut e = Entity::new(index);
                e.active = true;
                e
            };
            self.entities.insert(index, entity);
        }
        self.entities.get_mut(&index).unwrap()
    }

    /// Apply a delta update to an entity
    pub fn apply_delta(&mut self, index: u16, delta: EntityDelta) {
        let entity = self.get_or_create(index);
        // Presence in a packet means the entity is (back) in view, even if it
        // was previously removed.
        entity.active = true;
        delta.apply_to(entity);
        self.updated_this_frame.push(index);
    }

    /// Mark entity as removed
    pub fn remove_entity(&mut self, index: u16) {
        if let Some(entity) = self.entities.get_mut(&index) {
            entity.active = false;
        }
    }

    /// Get all active player positions
    /// Returns: Vec<(player_slot, origin, angles)>
    /// Sorted indices of all active entities (mirrors the engine's
    /// reconstructed frame entity list, which event packet_index references)
    pub fn active_indices_sorted(&self) -> Vec<u16> {
        let mut v: Vec<u16> = self
            .entities
            .iter()
            .filter(|(_, e)| e.active)
            .map(|(&i, _)| i)
            .collect();
        v.sort_unstable();
        v
    }

    /// Active non-player entities with their model index (grenades, C4, ...)
    pub fn get_object_positions(&self) -> Vec<(u16, u16, Vec3)> {
        let mut result = Vec::new();
        let first_object = self.max_players + 1;
        for (&idx, entity) in &self.entities {
            if idx < first_object || !entity.active || entity.model_index == 0 {
                continue;
            }
            let o = &entity.origin;
            if !(o.x.is_finite() && o.y.is_finite() && o.z.is_finite()) {
                continue;
            }
            if o.x.abs() > 8192.0 || o.y.abs() > 8192.0 || o.z.abs() > 8192.0 {
                continue;
            }
            if o.x == 0.0 && o.y == 0.0 && o.z == 0.0 {
                continue;
            }
            result.push((idx, entity.model_index, o.clone()));
        }
        result
    }

    pub fn get_player_positions(
        &self,
    ) -> Vec<(u8, Vec3, Vec3, Vec3, u8, u8, u8, u32, bool, u16, i16)> {
        let mut result = Vec::new();

        for idx in 1..=self.max_players {
            // First check active entities
            if let Some(entity) = self.entities.get(&idx) {
                if entity.active {
                    // Valid position: all coordinates non-zero and within map bounds
                    let has_valid_position = Self::is_valid_player_position(&entity.origin);

                    if has_valid_position {
                        let slot = (idx - 1) as u8;
                        result.push((
                            slot,
                            entity.origin.clone(),
                            entity.angles.clone(),
                            entity.velocity.clone(),
                            entity.gaitsequence,
                            entity.sequence,
                            entity.frame,
                            entity.effects,
                            entity.ducking,
                            entity.weapon_model,
                            entity.health,
                        ));
                        continue;
                    }
                }
            }

            // Fall back to baseline if no active entity
            if let Some(baseline) = self.baselines.get(&idx) {
                let has_valid_position = Self::is_valid_player_position(&baseline.origin);

                if has_valid_position {
                    let slot = (idx - 1) as u8;
                    result.push((
                        slot,
                        baseline.origin.clone(),
                        baseline.angles.clone(),
                        baseline.velocity.clone(),
                        0,
                        baseline.sequence,
                        baseline.frame,
                        baseline.effects,
                        baseline.ducking,
                        0,
                        baseline.health,
                    ));
                }
            }
        }

        result
    }

    /// Check if a position looks like a valid player position
    /// - At least 1 coordinate should be significant
    /// - Coordinates should be within reasonable map bounds
    fn is_valid_player_position(origin: &Vec3) -> bool {
        // At least 1 coordinate should be significant (> 10 units)
        let significant_coords = [
            origin.x.abs() > 10.0,
            origin.y.abs() > 10.0,
            origin.z.abs() > 10.0,
        ]
        .iter()
        .filter(|&&x| x)
        .count();

        if significant_coords < 1 {
            return false;
        }

        // All coordinates should be within map bounds
        // Most CS maps are within -4096 to 4096 for X/Y, and -500 to 500 for Z
        let within_bounds =
            origin.x.abs() < 5000.0 && origin.y.abs() < 5000.0 && origin.z.abs() < 5000.0;

        within_bounds
    }

    /// Get all active entities (for debugging)
    pub fn get_active_entities(&self) -> Vec<&Entity> {
        self.entities.values().filter(|e| e.active).collect()
    }

    /// Start a new frame (clear update tracking)
    pub fn begin_frame(&mut self) {
        self.updated_this_frame.clear();
    }

    /// Get entities updated this frame
    pub fn get_updated_entities(&self) -> &[u16] {
        &self.updated_this_frame
    }

    /// Reset all entity states (e.g., on map change)
    pub fn reset(&mut self) {
        self.entities.clear();
        self.baselines.clear();
        self.instance_baselines.clear();
        self.player_entities = [0; MAX_PLAYERS];
        self.updated_this_frame.clear();
    }

    /// Debug: print summary of entity states
    pub fn debug_summary(&self) -> String {
        let active_count = self.entities.values().filter(|e| e.active).count();
        let player_count = self
            .entities
            .values()
            .filter(|e| e.active && e.is_player())
            .count();

        format!(
            "Entities: {} total, {} active, {} players",
            self.entities.len(),
            active_count,
            player_count
        )
    }
}

impl Default for EntityState {
    fn default() -> Self {
        Self::new()
    }
}
