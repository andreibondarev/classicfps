/// Bit-level reader for GoldSrc network protocol data
/// Data is packed at the bit level for bandwidth efficiency

#[derive(Clone, Copy)]
pub struct BitReader<'a> {
    data: &'a [u8],
    bit_position: usize,
}

impl<'a> BitReader<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Self {
            data,
            bit_position: 0,
        }
    }

    /// Read up to 32 bits as unsigned integer
    pub fn read_bits(&mut self, count: usize) -> u32 {
        debug_assert!(count <= 32);
        let mut result: u32 = 0;

        for i in 0..count {
            let byte_index = self.bit_position / 8;
            let bit_index = self.bit_position % 8;

            if byte_index < self.data.len() {
                let bit = (self.data[byte_index] >> bit_index) & 1;
                result |= (bit as u32) << i;
            }
            self.bit_position += 1;
        }

        result
    }

    /// Read bits as signed integer (two's complement)
    pub fn read_signed_bits(&mut self, count: usize) -> i32 {
        let value = self.read_bits(count);
        // Sign extend
        let sign_bit = 1u32 << (count - 1);
        if value & sign_bit != 0 {
            // Negative number - extend sign
            (value | !((1u32 << count) - 1)) as i32
        } else {
            value as i32
        }
    }

    /// Read a single bit as boolean
    pub fn read_bit(&mut self) -> bool {
        self.read_bits(1) != 0
    }

    /// Read an 8-bit unsigned integer
    pub fn read_u8(&mut self) -> u8 {
        self.read_bits(8) as u8
    }

    /// Read a 16-bit unsigned integer
    pub fn read_u16(&mut self) -> u16 {
        self.read_bits(16) as u16
    }

    /// Read a 32-bit unsigned integer
    pub fn read_u32(&mut self) -> u32 {
        self.read_bits(32)
    }

    /// Read a 16-bit signed integer
    pub fn read_i16(&mut self) -> i16 {
        self.read_signed_bits(16) as i16
    }

    /// Read a null-terminated string
    pub fn read_string(&mut self) -> String {
        let mut bytes = Vec::new();
        loop {
            let byte = self.read_u8();
            if byte == 0 {
                break;
            }
            bytes.push(byte);
            // Safety limit
            if bytes.len() > 1024 {
                break;
            }
        }
        String::from_utf8_lossy(&bytes).to_string()
    }

    /// Read a GoldSrc bit-packed coordinate value (MSG_ReadBitCoord)
    /// Format: 1 bit int flag, 1 bit frac flag, then if either:
    ///   1 bit sign, optional 12-bit integer, optional 3-bit fraction
    pub fn read_coord(&mut self) -> f32 {
        let has_int = self.read_bit();
        let has_frac = self.read_bit();

        if !has_int && !has_frac {
            return 0.0;
        }

        let sign = self.read_bit();
        let mut value: f32 = 0.0;

        if has_int {
            let int_val = self.read_bits(12) as f32;
            value = int_val;
        }

        if has_frac {
            let frac_val = self.read_bits(3) as f32;
            value += frac_val / 8.0;
        }

        if sign {
            value = -value;
        }

        value
    }

    /// Read a coordinate vector (3 floats)
    pub fn read_coord_vec(&mut self) -> (f32, f32, f32) {
        let x_flag = self.read_bit();
        let y_flag = self.read_bit();
        let z_flag = self.read_bit();

        let x = if x_flag { self.read_coord() } else { 0.0 };
        let y = if y_flag { self.read_coord() } else { 0.0 };
        let z = if z_flag { self.read_coord() } else { 0.0 };

        (x, y, z)
    }

    /// Read angle (8-bit, scaled to 0-360)
    pub fn read_angle8(&mut self) -> f32 {
        let val = self.read_u8();
        (val as f32) * 360.0 / 256.0
    }

    /// Read angle (16-bit, scaled to 0-360)
    pub fn read_angle16(&mut self) -> f32 {
        let val = self.read_u16();
        (val as f32) * 360.0 / 65536.0
    }

    /// Read a high-resolution angle (used in some entity updates)
    pub fn read_hiresangle(&mut self) -> f32 {
        let val = self.read_i16();
        (val as f32) * (360.0 / 65536.0)
    }

    /// Get remaining bits available to read
    pub fn bits_remaining(&self) -> usize {
        let total_bits = self.data.len() * 8;
        if self.bit_position >= total_bits {
            0
        } else {
            total_bits - self.bit_position
        }
    }

    /// Get current bit position
    pub fn bit_position(&self) -> usize {
        self.bit_position
    }

    /// Align to next byte boundary
    pub fn byte_align(&mut self) {
        let remainder = self.bit_position % 8;
        if remainder != 0 {
            self.bit_position += 8 - remainder;
        }
    }

    /// Skip n bits
    pub fn skip_bits(&mut self, count: usize) {
        self.bit_position += count;
    }

    /// Skip n bytes
    pub fn skip_bytes(&mut self, count: usize) {
        self.bit_position += count * 8;
    }

    /// Read raw bytes (byte-aligned)
    pub fn read_bytes(&mut self, count: usize) -> Vec<u8> {
        self.byte_align();
        let mut result = Vec::with_capacity(count);
        for _ in 0..count {
            result.push(self.read_u8());
        }
        result
    }

    /// Check if we've reached the end of data
    pub fn is_eof(&self) -> bool {
        self.bits_remaining() == 0
    }

    /// Peek at next bits without advancing position
    pub fn peek_bits(&self, count: usize) -> u32 {
        let mut temp = Self {
            data: self.data,
            bit_position: self.bit_position,
        };
        temp.read_bits(count)
    }

    /// Peek at next bytes without advancing position (byte-aligned)
    pub fn peek_bytes(&self, count: usize) -> Vec<u8> {
        let mut temp = Self {
            data: self.data,
            bit_position: self.bit_position,
        };
        temp.byte_align();
        let mut result = Vec::with_capacity(count);
        for _ in 0..count {
            if temp.bits_remaining() >= 8 {
                result.push(temp.read_u8());
            }
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_read_bits() {
        // 0b10110100 = 0xB4
        let data = [0xB4];
        let mut reader = BitReader::new(&data);
        assert_eq!(reader.read_bits(1), 0); // bit 0
        assert_eq!(reader.read_bits(1), 0); // bit 1
        assert_eq!(reader.read_bits(1), 1); // bit 2
        assert_eq!(reader.read_bits(1), 0); // bit 3
        assert_eq!(reader.read_bits(1), 1); // bit 4
        assert_eq!(reader.read_bits(1), 1); // bit 5
        assert_eq!(reader.read_bits(1), 0); // bit 6
        assert_eq!(reader.read_bits(1), 1); // bit 7
    }

    #[test]
    fn test_read_u8() {
        let data = [0x42, 0xFF];
        let mut reader = BitReader::new(&data);
        assert_eq!(reader.read_u8(), 0x42);
        assert_eq!(reader.read_u8(), 0xFF);
    }

    #[test]
    fn test_signed_bits() {
        let data = [0xFF]; // All 1s
        let mut reader = BitReader::new(&data);
        // Reading 4 bits of 1s (0b1111) as signed = -1
        assert_eq!(reader.read_signed_bits(4), -1);
    }

    #[test]
    fn test_read_string() {
        let data = [b'H', b'i', 0];
        let mut reader = BitReader::new(&data);
        assert_eq!(reader.read_string(), "Hi");
    }
}
