//! Private register-file transfers at native block and helper boundaries.
//! Pair only adjacent guest slots within the requested cache subset. These
//! are executor-private registers, not ordered guest-memory accesses.
const a64 = @import("arm64_encode");

pub fn transfer(assembler: anytype, ids: anytype, hosts: []const a64.Reg, base: a64.Reg, written: u16, store: bool) !void {
    var visited: u16 = 0;
    for (ids, 0..) |id, slot| {
        const bit = @as(u16, 1) << @intCast(slot);
        if (visited & bit != 0) continue;
        visited |= bit;
        const guest: u32 = @intFromEnum(id);
        if (store and written & (@as(u16, 1) << @intCast(guest)) == 0) continue;
        var partner: ?usize = null;
        for (ids[slot + 1 ..], slot + 1..) |other, other_slot| {
            if (visited & (@as(u16, 1) << @intCast(other_slot)) != 0) continue;
            const peer: u32 = @intFromEnum(other);
            if (store and written & (@as(u16, 1) << @intCast(peer)) == 0) continue;
            if (guest + 1 == peer or peer + 1 == guest) {
                partner = other_slot;
                break;
            }
        }
        if (partner) |peer_slot| {
            visited |= @as(u16, 1) << @intCast(peer_slot);
            const peer: u32 = @intFromEnum(ids[peer_slot]);
            const low = if (guest < peer) slot else peer_slot;
            const high = if (guest < peer) peer_slot else slot;
            const offset: i32 = @intCast(@min(guest, peer) * 8);
            try assembler.emit(if (store)
                a64.stp(.signed_offset, hosts[low], hosts[high], base, offset).?
            else
                a64.ldp(.signed_offset, hosts[low], hosts[high], base, offset).?);
        } else {
            try assembler.emit(if (store)
                a64.strImm(.doubleword, hosts[slot], base, guest * 8).?
            else
                a64.ldrImm(.doubleword, hosts[slot], base, guest * 8).?);
        }
    }
}
