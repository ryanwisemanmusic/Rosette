//! Xenos fetch constants, kept apart from the live register file.

const types = @import("types.zig");
const texture = @import("texture.zig");
const vertex = @import("vertex.zig");
const provenance = @import("provenance.zig");

pub const FetchConstantType = types.FetchConstantType;
pub const TextureDimension = types.TextureDimension;
pub const Endian = types.Endian;
pub const TextureSlotDiagnosis = types.TextureSlotDiagnosis;
pub const diagnoseTextureSlot = types.diagnoseTextureSlot;
pub const TextureFetch = texture.TextureFetch;
pub const VertexFetch = vertex.VertexFetch;
pub const TextureFetchProvenance = provenance.TextureFetchProvenance;
pub const WritePattern = provenance.WritePattern;

test {
    _ = types;
    _ = texture;
    _ = vertex;
    _ = provenance;
}
