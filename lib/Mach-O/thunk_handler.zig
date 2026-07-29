//! Synthetic runtime thunk and import binding handlers.
//! Extracted from MachOState (process.zig) to reduce file size.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports.
//! The type is inferred at the call site as `*MachOState`.

const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");
const exit_diagnostics = @import("exit_diagnostics");
const tlv_runtime = @import("guest_abi").tlv_runtime;
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const BOUND_IMPORT_THUNK_BASE = @import("constants.zig").BOUND_IMPORT_THUNK_BASE;

pub fn handleSyntheticRuntimeThunk(self: anytype) bool {
    const thunk = compat_runtime.syntheticThunk(self.regs.rip) orelse return false;
    const source_begin = self.regs.rsi;
    const source_end = self.regs.rdx;

    switch (thunk) {
        .ctype_toupper_char => self.regs.rax = std.ascii.toUpper(@as(u8, @truncate(self.regs.rsi))),
        .ctype_tolower_char => self.regs.rax = std.ascii.toLower(@as(u8, @truncate(self.regs.rsi))),
        .ctype_toupper_range, .ctype_tolower_range => {
            if (source_end < source_begin) {
                self.regs.rax = source_begin;
            } else if (self.guestMemory(source_begin, source_end - source_begin)) |bytes| {
                for (bytes) |*byte| {
                    byte.* = if (thunk == .ctype_toupper_range) std.ascii.toUpper(byte.*) else std.ascii.toLower(byte.*);
                }
                self.regs.rax = source_end;
            } else {
                self.regs.rax = source_begin;
            }
        },
        .ctype_widen_char, .ctype_narrow_char => self.regs.rax = self.regs.rsi & 0xFF,
        .ctype_widen_range => {
            const count = source_end -| source_begin;
            const source = self.guestMemoryConst(source_begin, count);
            const destination = self.guestMemory(self.regs.rcx, count);
            if (source != null and destination != null) std.mem.copyForwards(u8, destination.?, source.?);
            self.regs.rax = source_end;
        },
        .ctype_narrow_range => {
            const count = source_end -| source_begin;
            const source = self.guestMemoryConst(source_begin, count);
            const destination = self.guestMemory(self.regs.r8, count);
            if (source != null and destination != null) std.mem.copyForwards(u8, destination.?, source.?);
            self.regs.rax = source_end;
        },
        .locale_destroy => {
            self.regs.rax = 0;
        },
        .locale_has_facet => {
            self.regs.rax = 1;
        },
        .locale_use_facet => {
            self.regs.rax = self.compat.locale_impl_facet;
        },
        .xmodule_get_name => {
            if (self.internal_targets.xmodule_empty_string == 0) {
                const empty = self.guestAlloc(1, 1) orelse {
                    self.regs.rax = 0;
                    self.regs.rdx = 0;
                    return false;
                };
                if (self.guestMemory(empty, 1)) |b| b[0] = 0;
                self.internal_targets.xmodule_empty_string = empty;
            }
            self.regs.rax = self.internal_targets.xmodule_empty_string;
            self.regs.rdx = 0;
        },
        .streambuf_imbue => {
            // basic_streambuf::imbue is a void customization hook. Modeled
            // stream buffers own no host locale state, so retaining the
            // replacement locale in basic_ios is sufficient.
            self.regs.rax = 0;
        },
    }

    const return_address = self.pop();
    if (self.verbose_trace) machoCapturePrint("    [synthetic runtime] {s} -> rax=0x{x} return=0x{x}\n", .{ @tagName(thunk), self.regs.rax, return_address });
    if (return_address == 0) {
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        self.terminated = true;
    } else {
        self.regs.rip = return_address;
    }
    return true;
}

pub fn handleTlvBootstrap(self: anytype) bool {
    if (!tlv_runtime.Runtime.handles(self.regs.rip)) return false;
    const descriptor = self.regs.rdi;
    self.regs.rax = self.tlv.resolve(self, descriptor, self.active_guest_thread) orelse 0;
    const return_address = self.pop();
    if (self.regs.rax == 0 or return_address == 0 or !self.isExecutableAddress(return_address)) {
        self.terminateForInvalidControlTransfer(.{
            .kind = "Darwin TLV bootstrap return",
            .instruction_address = tlv_runtime.bootstrap_thunk,
            .operand_address = descriptor,
            .target_address = return_address,
        });
    } else {
        self.regs.rip = return_address;
    }
    return true;
}

pub fn handleBoundImportThunk(self: anytype) bool {
    if (self.regs.rip < BOUND_IMPORT_THUNK_BASE) return false;
    for (self.bound_import_thunks) |thunk| {
        if (thunk.address != self.regs.rip) continue;
        self.handleDirectImportCall(.{
            .name = thunk.name,
            .dylib = thunk.dylib,
            .stub_address = thunk.address,
            .lazy_pointer_address = 0,
            .symbol_index = 0,
        });
        return true;
    }
    return false;
}

pub fn handleDynamicLibraryThunk(self: anytype) bool {
    const thunk_address = self.regs.rip;
    const virtual_sleep_calls_before = self.dynamic_forwarder.virtualSleepCallCount();
    if (!self.dynamic_forwarder.dispatchGuestSymbol(self, thunk_address)) return false;
    const return_address = self.pop();
    if (self.verbose_trace) {
        machoCapturePrint(
            "    [dynamic loader thunk] address=0x{x} -> rax=0x{x} return=0x{x}\n",
            .{ thunk_address, self.regs.rax, return_address },
        );
    }
    if (return_address == 0 or !self.isExecutableAddress(return_address)) {
        self.terminateForInvalidControlTransfer(.{
            .kind = "dynamic-library thunk return",
            .instruction_address = thunk_address,
            .target_address = return_address,
        });
    } else {
        self.regs.rip = return_address;
        if (self.dynamic_forwarder.virtualSleepCallCount() != virtual_sleep_calls_before) {
            _ = self.handleVirtualSleepSchedulingBoundary("libc++ virtual sleep thunk");
        }
    }
    return true;
}
