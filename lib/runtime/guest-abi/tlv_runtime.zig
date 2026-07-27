const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

pub const bootstrap_thunk: u64 = 0xFFFF_F700_0000_0000;
const descriptor_size: u64 = 3 * @sizeOf(u64);
const storage_size: u64 = 4096;
const max_slots = 512;

const Slot = struct {
    descriptor: u64 = 0,
    thread: u64 = 0,
    storage: u64 = 0,
};

pub const Runtime = struct {
    slots: [max_slots]Slot = [_]Slot{.{}} ** max_slots,
    descriptor_count: u64 = 0,
    allocation_count: u64 = 0,

    pub fn installDescriptors(self: *Runtime, state: anytype) void {
        const section = state.metadata.sectionNamed("__DATA", "__thread_vars") orelse return;
        var descriptor = section.address;
        const end = section.address +| section.size;
        while (descriptor + descriptor_size <= end) : (descriptor += descriptor_size) {
            if (state.guestMemory(descriptor, descriptor_size) == null) break;
            state.write64(descriptor, bootstrap_thunk);
            self.descriptor_count +|= 1;
        }
        if (self.descriptor_count != 0) {
            machoCapturePrint("macho-processor: installed Darwin TLV bootstrap for {d} descriptor(s)\n", .{self.descriptor_count});
        }
    }

    pub fn handles(address: u64) bool {
        return address == bootstrap_thunk;
    }

    pub fn resolve(self: *Runtime, state: anytype, descriptor: u64, thread: u64) ?u64 {
        const thread_key = if (thread == 0) @as(u64, 1) else thread;
        for (&self.slots) |*slot| {
            if (slot.storage != 0 and slot.descriptor == descriptor and slot.thread == thread_key) return slot.storage;
        }
        for (&self.slots) |*slot| {
            if (slot.storage != 0) continue;
            const storage = state.guestAlloc(storage_size, 16) orelse return null;
            if (state.guestMemory(storage, storage_size)) |bytes| @memset(bytes, 0);
            slot.* = .{ .descriptor = descriptor, .thread = thread_key, .storage = storage };
            self.allocation_count +|= 1;
            return storage;
        }
        return null;
    }
};
