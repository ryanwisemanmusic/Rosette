//! Generic checks for fixed-width audio buffers and aligned stack boundaries.

pub fn isVectorSized(bytes: u32, sample_bytes: u32, vector_bytes: u32) bool {
    return bytes != 0 and sample_bytes != 0 and vector_bytes != 0 and
        vector_bytes % sample_bytes == 0 and bytes % vector_bytes == 0;
}

pub fn isAligned(address: u64, alignment: u32) bool {
    return alignment != 0 and address % alignment == 0;
}
