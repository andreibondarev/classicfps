/// Delta compression definitions for GoldSrc entity updates
///
/// The GoldSrc engine uses delta compression to efficiently transmit entity state changes.
/// Delta definitions are sent at signon time via SVC_DELTADESCRIPTION; each definition's
/// entries are themselves delta-encoded against the hardcoded `delta_description_t`
/// meta-definition below.
use bitflags::bitflags;
use std::collections::HashMap;
use std::rc::Rc;

bitflags! {
    /// Field type flags — these are the engine's DT_* constants and come off the wire,
    /// so the bit values must match GoldSrc exactly (delta.h).
    #[derive(Clone, Copy, Debug, Default, PartialEq)]
    pub struct DeltaFlags: u32 {
        const BYTE = 1 << 0;            // DT_BYTE
        const SHORT = 1 << 1;           // DT_SHORT
        const FLOAT = 1 << 2;           // DT_FLOAT
        const INTEGER = 1 << 3;         // DT_INTEGER
        const ANGLE = 1 << 4;           // DT_ANGLE (scaled 360/2^bits)
        const TIMEWINDOW_8 = 1 << 5;    // DT_TIMEWINDOW_8
        const TIMEWINDOW_BIG = 1 << 6;  // DT_TIMEWINDOW_BIG
        const STRING = 1 << 7;          // DT_STRING
        const SIGNED = 1 << 31;         // DT_SIGNED (sign bit precedes magnitude)
    }
}

/// A single field in a delta descriptor
#[derive(Clone, Debug)]
pub struct DeltaFieldDef {
    pub name: String,
    pub bits: u8,
    pub divisor: f32,
    pub pre_multiplier: f32,
    pub flags: DeltaFlags,
}

impl DeltaFieldDef {
    pub fn new(name: String, bits: u8, divisor: f32, pre_multiplier: f32, flags: u32) -> Self {
        Self {
            name,
            bits,
            divisor,
            pre_multiplier,
            flags: DeltaFlags::from_bits_retain(flags),
        }
    }
}

/// A complete delta definition for an entity type
#[derive(Clone, Debug, Default)]
pub struct DeltaDefinition {
    pub name: String,
    pub fields: Vec<DeltaFieldDef>,
}

impl DeltaDefinition {
    pub fn new(name: String) -> Self {
        Self {
            name,
            fields: Vec::new(),
        }
    }

    pub fn add_field(&mut self, field: DeltaFieldDef) {
        self.fields.push(field);
    }
}

/// The hardcoded meta-definition used to decode SVC_DELTADESCRIPTION entries
/// (g_MetaDelta in the engine).
pub fn meta_delta_description() -> DeltaDefinition {
    let f = |name: &str, bits: u8, divisor: f32, flags: DeltaFlags| DeltaFieldDef {
        name: name.to_string(),
        bits,
        divisor,
        pre_multiplier: 1.0,
        flags,
    };
    DeltaDefinition {
        name: "delta_description_t".to_string(),
        fields: vec![
            f("flags", 32, 1.0, DeltaFlags::INTEGER),
            f("name", 8, 1.0, DeltaFlags::STRING),
            f("offset", 16, 1.0, DeltaFlags::INTEGER),
            f("size", 8, 1.0, DeltaFlags::INTEGER),
            f("nBits", 8, 1.0, DeltaFlags::INTEGER),
            f("divisor", 32, 4000.0, DeltaFlags::FLOAT),
            f("preMultiplier", 32, 4000.0, DeltaFlags::FLOAT),
        ],
    }
}

/// Registry of all delta definitions learned from SVC_DELTADESCRIPTION
#[derive(Debug, Default)]
pub struct DeltaRegistry {
    definitions: HashMap<String, Rc<DeltaDefinition>>,
}

impl DeltaRegistry {
    pub fn new() -> Self {
        Self {
            definitions: HashMap::new(),
        }
    }

    pub fn register(&mut self, def: DeltaDefinition) {
        self.definitions.insert(def.name.clone(), Rc::new(def));
    }

    pub fn get(&self, name: &str) -> Option<Rc<DeltaDefinition>> {
        self.definitions.get(name).cloned()
    }

    pub fn clear(&mut self) {
        self.definitions.clear();
    }
}

/// Simplified entity state for tracking player positions.
/// Components are individually optional: a delta only carries the fields that
/// changed, and unmentioned components must keep their previous value.
#[derive(Clone, Debug, Default)]
pub struct EntityDelta {
    pub origin: [Option<f32>; 3],
    pub angles: [Option<f32>; 3],
    pub velocity: [Option<f32>; 3],
    pub modelindex: Option<u16>,
    pub sequence: Option<u8>,
    pub gaitsequence: Option<u8>,
    pub weaponmodel: Option<u16>,
    pub frame: Option<u8>,
    pub effects: Option<u8>,
    pub solid: Option<u8>,
    pub health: Option<i16>,
    pub usehull: Option<u8>,
}

impl EntityDelta {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn has_origin(&self) -> bool {
        self.origin.iter().any(|c| c.is_some())
    }

    /// Apply this delta to an existing entity state
    pub fn apply_to(&self, entity: &mut crate::entity::Entity) {
        if let Some(x) = self.origin[0] {
            entity.origin.x = x;
        }
        if let Some(y) = self.origin[1] {
            entity.origin.y = y;
        }
        if let Some(z) = self.origin[2] {
            entity.origin.z = z;
        }
        if let Some(x) = self.angles[0] {
            entity.angles.x = x;
        }
        if let Some(y) = self.angles[1] {
            entity.angles.y = y;
        }
        if let Some(z) = self.angles[2] {
            entity.angles.z = z;
        }
        if let Some(x) = self.velocity[0] {
            entity.velocity.x = x;
        }
        if let Some(y) = self.velocity[1] {
            entity.velocity.y = y;
        }
        if let Some(z) = self.velocity[2] {
            entity.velocity.z = z;
        }
        if let Some(modelindex) = self.modelindex {
            entity.model_index = modelindex;
        }
        if let Some(g) = self.gaitsequence {
            entity.gaitsequence = g;
        }
        if let Some(sequence) = self.sequence {
            entity.sequence = sequence;
        }
        if let Some(frame) = self.frame {
            entity.frame = frame;
        }
        if let Some(w) = self.weaponmodel {
            entity.weapon_model = w;
        }
        if let Some(effects) = self.effects {
            entity.effects = effects as u32;
        }
        if let Some(solid) = self.solid {
            entity.solid = solid;
        }
        if let Some(health) = self.health {
            entity.health = health;
        }
        if let Some(usehull) = self.usehull {
            entity.ducking = usehull != 0;
        }
    }
}
