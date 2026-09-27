//! Scalar CRT floating-point imports. Host computation is exact for these
//! pure operations; all register and return-address effects remain delegated
//! through the Rosette Windows ABI adapter.
const std = @import("std");

/// Select CPU and thread-local import state from a bound Windows guest
/// execution context when one is active, while preserving the standalone
/// state shape used by the generic runtime helpers and tests.
fn guestStateField(state: anytype, comptime field: []const u8) *@FieldType(@TypeOf(state.*), field) {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "windowsGuestContextField")) {
        return state.windowsGuestContextField(field);
    }
    return &@field(state.*, field);
}

// ---------------------------------------------------------------------------
// The C runtime's floating-point surface.
//
// These are the most dangerous names in the whole import table, and the least
// obviously so. A refused Win32 call tells the guest it failed; a maths
// function that returns the wrong number is indistinguishable from one that
// returned the right one, and the guest carries the answer forward into a
// matrix, a timing calculation or a shader constant. Twenty-two of them were
// falling through to the ABI fallback, which hands back a zero - a perfectly
// plausible value for `sin`, `atan` or `log10` and a completely wrong one.
//
// Every one is a pure function the host computes exactly, so there is no
// modelling decision here at all: the only reason they were missing is that
// nobody had written them down.
//
// Microsoft x64 passes the first four floating-point arguments in xmm0..xmm3
// and returns in xmm0. Integer and floating arguments share the four
// positions, so `scalbn(double, int)` takes its double in xmm0 and its int in
// edx - the second *slot*, not the second integer register.

fn guestDouble(state: anytype, slot: usize) f64 {
    return @bitCast(std.mem.readInt(u64, guestStateField(state, "xmm").*[slot][0..8], .little));
}

fn guestFloat(state: anytype, slot: usize) f32 {
    return @bitCast(std.mem.readInt(u32, guestStateField(state, "xmm").*[slot][0..4], .little));
}

pub fn returnGuestDouble(state: anytype, value: f64) void {
    // Only the low quadword is the result; the rest of the register is
    // architecturally undefined on return, and zeroing it keeps a later
    // vector read from seeing whatever the last call left there.
    @memset(guestStateField(state, "xmm").*[0][0..], 0);
    std.mem.writeInt(u64, guestStateField(state, "xmm").*[0][0..8], @bitCast(value), .little);
}

fn returnGuestFloat(state: anytype, value: f32) void {
    @memset(guestStateField(state, "xmm").*[0][0..], 0);
    std.mem.writeInt(u32, guestStateField(state, "xmm").*[0][0..4], @bitCast(value), .little);
}

/// The C runtime maths functions Rosette computes exactly.
///
/// Returns false for a name this does not own, so the caller carries on down
/// its chain.
pub fn tryFunction(comptime host: type, state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const Unary = struct { name: []const u8, apply: *const fn (f64) f64 };
    const unary = [_]Unary{
        .{ .name = "acos", .apply = struct {
            fn f(x: f64) f64 {
                return std.math.acos(x);
            }
        }.f },
        .{ .name = "asin", .apply = struct {
            fn f(x: f64) f64 {
                return std.math.asin(x);
            }
        }.f },
        .{ .name = "atan", .apply = struct {
            fn f(x: f64) f64 {
                return std.math.atan(x);
            }
        }.f },
        .{ .name = "cbrt", .apply = struct {
            fn f(x: f64) f64 {
                return std.math.cbrt(x);
            }
        }.f },
        .{ .name = "cosh", .apply = struct {
            fn f(x: f64) f64 {
                return std.math.cosh(x);
            }
        }.f },
        .{ .name = "sinh", .apply = struct {
            fn f(x: f64) f64 {
                return std.math.sinh(x);
            }
        }.f },
        .{ .name = "tan", .apply = struct {
            fn f(x: f64) f64 {
                return std.math.tan(x);
            }
        }.f },
        .{ .name = "tanh", .apply = struct {
            fn f(x: f64) f64 {
                return std.math.tanh(x);
            }
        }.f },
        .{ .name = "exp2", .apply = struct {
            fn f(x: f64) f64 {
                return std.math.exp2(x);
            }
        }.f },
        .{ .name = "log10", .apply = struct {
            fn f(x: f64) f64 {
                return std.math.log10(x);
            }
        }.f },
    };
    for (unary) |entry| {
        if (!std.mem.eql(u8, name, entry.name)) continue;
        returnGuestDouble(state, entry.apply(guestDouble(state, 0)));
        guestStateField(state, "windows_last_error").* = 0;
        host.completeCall(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "exp2f")) {
        returnGuestFloat(state, std.math.exp2(guestFloat(state, 0)));
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "log2f")) {
        returnGuestFloat(state, std.math.log2(guestFloat(state, 0)));
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "hypot") or std.mem.eql(u8, name, "_hypot")) {
        // std.math.hypot avoids the overflow that a naive sqrt(x*x + y*y)
        // produces for large operands, which is the whole reason the C
        // library exposes it separately from sqrt.
        returnGuestDouble(state, std.math.hypot(guestDouble(state, 0), guestDouble(state, 1)));
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "nextafter")) {
        const from = guestDouble(state, 0);
        const toward = guestDouble(state, 1);
        returnGuestDouble(state, nextAfterDouble(from, toward));
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_copysign") or std.mem.eql(u8, name, "copysign")) {
        returnGuestDouble(state, std.math.copysign(guestDouble(state, 0), guestDouble(state, 1)));
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "scalbn") or std.mem.eql(u8, name, "_scalb") or
        std.mem.eql(u8, name, "ldexp"))
    {
        // The exponent is an int in the *second argument slot*, which for a
        // call whose first argument is a double means edx.
        const exponent: i32 = @bitCast(@as(u32, @truncate(guestStateField(state, "regs").*.rdx)));
        returnGuestDouble(state, std.math.ldexp(guestDouble(state, 0), exponent));
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "frexp")) {
        // `double frexp(double value, int *exp)`: the significand comes back
        // in xmm0 and the exponent is written through the pointer. Dropping
        // the store leaves the caller reading its own uninitialised stack.
        const value = guestDouble(state, 0);
        const parts = std.math.frexp(value);
        const exponent_out = guestStateField(state, "regs").*.rdx;
        if (exponent_out != 0 and state.guestMemory(exponent_out, 4) != null) {
            state.write32(exponent_out, @bitCast(@as(i32, @intCast(parts.exponent))));
        }
        returnGuestDouble(state, parts.significand);
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_finite")) {
        const value = guestDouble(state, 0);
        guestStateField(state, "regs").*.rax = if (std.math.isFinite(value)) 1 else 0;
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_isnan")) {
        guestStateField(state, "regs").*.rax = if (std.math.isNan(guestDouble(state, 0))) 1 else 0;
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "lrintf")) {
        guestStateField(state, "regs").*.rax = @bitCast(host.roundToI64(state, @floatCast(guestFloat(state, 0))));
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "nanf")) {
        // `float nanf(const char *tag)`. The tag selects a payload; every
        // caller in practice passes "" and wants a quiet NaN.
        returnGuestFloat(state, std.math.nan(f32));
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__setusermatherr")) {
        // Installs a callback the CRT invokes on a domain error. Rosette
        // computes with IEEE semantics and raises none, so there is nothing
        // to call back; accepting the registration is the honest answer,
        // because refusing it would make the CRT think it cannot report.
        host.returnZeroCall(state, direct_return_rip);
        return true;
    }
    return false;
}

/// The next representable double from `from` toward `toward`.
///
/// Written out rather than reached for in std, because the edge cases are the
/// only reason a caller uses this function: equal operands return the target
/// unchanged, a NaN on either side propagates, and stepping away from zero
/// must cross into the smallest subnormal rather than skipping it.
pub fn nextAfterDouble(from: f64, toward: f64) f64 {
    if (std.math.isNan(from) or std.math.isNan(toward)) return std.math.nan(f64);
    if (from == toward) return toward;
    if (from == 0.0) {
        const smallest: f64 = @bitCast(@as(u64, 1));
        return if (toward > 0.0) smallest else -smallest;
    }
    var bits: u64 = @bitCast(from);
    // Away from zero increments the magnitude; toward zero decrements it.
    if ((toward > from) == (from > 0.0)) bits += 1 else bits -= 1;
    return @bitCast(bits);
}

test "nextafter preserves equal values and steps from zero" {
    const positive_zero_step = nextAfterDouble(0.0, 1.0);
    const negative_zero_step = nextAfterDouble(0.0, -1.0);
    try std.testing.expectEqual(@as(u64, 1), @as(u64, @bitCast(positive_zero_step)));
    try std.testing.expectEqual(@as(u64, 0x8000_0000_0000_0001), @as(u64, @bitCast(negative_zero_step)));
    try std.testing.expectEqual(@as(f64, 1.0), nextAfterDouble(1.0, 1.0));
}

test "nextafter advances one representable value in either direction" {
    const above_one = nextAfterDouble(1.0, 2.0);
    const below_one = nextAfterDouble(1.0, 0.0);
    try std.testing.expect(above_one > 1.0);
    try std.testing.expect(below_one < 1.0);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(f64, 1.0))) + 1, @as(u64, @bitCast(above_one)));
    try std.testing.expectEqual(@as(u64, @bitCast(@as(f64, 1.0))) - 1, @as(u64, @bitCast(below_one)));
}

test "nextafter propagates NaN" {
    const result = nextAfterDouble(std.math.nan(f64), 0.0);
    try std.testing.expect(std.math.isNan(result));
}
