const std = @import("std");

/// Memory Access Safety Module
/// Provides generalized solutions for memory access validation, sign-extension detection,
/// and memory access instrumentation for emulators, debuggers, and memory-intensive applications.

/// Error types for memory access failures
pub const Error = error{
    SignExtensionBug,
    InvalidAddress,
    PermissionDenied,
    StackCorruption,
};

/// Sign extension detection
pub const SignExtensionAuditor = struct {
    /// Sign extension pattern enum
    pub const Pattern = enum {
        none,
        likely_32bit_sign_extend,
        likely_16bit_sign_extend,
        likely_8bit_sign_extend,
    };
    
    /// Detect if a 64-bit address might be from incorrectly sign-extended 32-bit value
    pub fn detectSignExtensionBug(addr: u64) bool {
        // Check if address is in upper half of 64-bit space (bit 63 set)
        // and if lower 32 bits indicate it could be from sign-extended 32-bit
        const upper_half = (addr & 0x8000000000000000) != 0;
        const sign_bit_32 = (addr & 0x80000000) != 0;
        
        // If upper half is set and bit 31 is set, likely sign-extension
        // Also check if the upper 32 bits are all 1s (characteristic of sign-extension)
        const upper_32_ones = (addr & 0xFFFFFFFF00000000) == 0xFFFFFFFF00000000;
        
        return upper_half and (sign_bit_32 or upper_32_ones);
    }
    
    /// Get the original 32-bit value if this looks like a sign-extension bug
    pub fn extractOriginal32Bit(addr: u64) u32 {
        return @truncate(addr);
    }
    
    /// Check if address shows sign-extension pattern
    pub fn getSignExtensionPattern(addr: u64) Pattern {
        if (addr & 0xFFFFFFFF80000000 == 0xFFFFFFFF80000000) {
            // Upper 33 bits are 1s, could be 31-bit sign-extension
            return .likely_32bit_sign_extend;
        }
        if (addr & 0xFFFFFFFFFFFF8000 == 0xFFFFFFFFFFFF8000) {
            // Upper 48 bits are 1s, could be 16-bit sign-extension
            return .likely_16bit_sign_extend;
        }
        if (addr & 0xFFFFFFFFFFFFFF80 == 0xFFFFFFFFFFFFFF80) {
            // Upper 57 bits are 1s, could be 8-bit sign-extension
            return .likely_8bit_sign_extend;
        }
        return .none;
    }
};

/// Address validation with region whitelist
pub const AddressValidation = struct {
    /// Memory region definition for validation
    pub const MemoryRegion = struct {
        base: u64,
        size: u64,
        name: []const u8,
        writable: bool = true,
        executable: bool = false,
        
        pub fn contains(self: *const MemoryRegion, addr: u64) bool {
            return addr >= self.base and addr < (self.base + self.size);
        }
        
        pub fn end(self: *const MemoryRegion) u64 {
            return self.base + self.size;
        }
    };
    
    /// Region whitelist (fixed size for simplicity)
    regions: [16]MemoryRegion,
    region_count: usize,
    
    pub fn init() AddressValidation {
        return .{
            .regions = undefined,
            .region_count = 0,
        };
    }
    
    /// Add a memory region to the whitelist
    pub fn addRegion(self: *AddressValidation, base: u64, size: u64, name: []const u8, writable: bool, executable: bool) !void {
        if (self.region_count >= self.regions.len) return error.TooManyRegions;
        self.regions[self.region_count] = .{
            .base = base,
            .size = size,
            .name = name,
            .writable = writable,
            .executable = executable,
        };
        self.region_count += 1;
    }
    
    /// Check if an address is valid (within any whitelisted region)
    pub fn isValidAddress(self: *const AddressValidation, addr: u64) bool {
        for (self.regions[0..self.region_count]) |region| {
            if (region.contains(addr)) return true;
        }
        return false;
    }
    
    /// Check if an address range is valid (all bytes within whitelisted regions)
    pub fn isValidAddressRange(self: *const AddressValidation, addr: u64, size: u64) bool {
        if (size == 0) return true;
        
        const end_addr = addr + size;
        if (end_addr <= addr) return false; // Overflow check
        
        for (self.regions[0..self.region_count]) |region| {
            if (addr >= region.base and end_addr <= region.end()) return true;
        }
        return false;
    }
    
    /// Check if address is valid for specific access type
    pub fn isValidForAccessType(self: *const AddressValidation, addr: u64, is_write: bool, is_execute: bool) bool {
        for (self.regions[0..self.region_count]) |region| {
            if (region.contains(addr)) {
                if (is_write and !region.writable) return false;
                if (is_execute and !region.executable) return false;
                return true;
            }
        }
        return false;
    }
    
    /// Validate stack-relative access (within reasonable bounds of stack pointer)
    pub fn validateStackAccess(self: *const AddressValidation, addr: u64, stack_pointer: u64, max_stack_offset: u64) bool {
        _ = self;
        // Allow both positive and negative offsets within reasonable range
        const offset = if (addr >= stack_pointer)
            addr - stack_pointer
        else
            stack_pointer - addr;
        
        return offset <= max_stack_offset;
    }
};

/// Memory access instrumentation
pub const MemoryAccessInstrumentation = struct {
    /// Memory access record for logging
    pub const AccessRecord = struct {
        timestamp: u64,
        rip: u64,
        address: u64,
        size: u64,
        is_write: bool,
        is_execute: bool,
        successful: bool,
        error_type: ?[]const u8,
        
        pub fn format(self: *const AccessRecord, writer: anytype) !void {
            try writer.print("{x:0>16} | RIP: {x:0>8} | Addr: {x:0>16} | Size: {x:3} | {s} | {s} | {s}", 
                .{self.timestamp, self.rip, self.address, self.size, 
                  if (self.is_write) "W" else "R",
                  if (self.is_execute) "X" else "-",
                  if (self.successful) "OK" else "FAIL"});
            
            if (self.error_type) |err| {
                try writer.print(" | Error: {s}", .{err});
            }
        }
    };
    
    access_log: [100]AccessRecord,
    log_index: usize,
    max_log_size: usize,
    access_count: u64,
    fault_count: u64,
    
    pub fn init(max_log_size: usize) MemoryAccessInstrumentation {
        return .{
            .access_log = undefined,
            .log_index = 0,
            .max_log_size = if (max_log_size > 100) 100 else max_log_size,
            .access_count = 0,
            .fault_count = 0,
        };
    }
    
    /// Record a memory access attempt
    pub fn recordAccess(self: *MemoryAccessInstrumentation, rip: u64, address: u64, size: u64, is_write: bool, is_execute: bool, successful: bool, error_type: ?[]const u8) !void {
        const timestamp = self.access_count; // Use access count as simple timestamp
        
        self.access_log[self.log_index] = .{
            .timestamp = timestamp,
            .rip = rip,
            .address = address,
            .size = size,
            .is_write = is_write,
            .is_execute = is_execute,
            .successful = successful,
            .error_type = error_type,
        };
        
        self.log_index = (self.log_index + 1) % self.max_log_size;
        self.access_count += 1;
        if (!successful) self.fault_count += 1;
    }
    
    /// Get recent access records
    pub fn getRecentAccesses(self: *const MemoryAccessInstrumentation, count: usize) []const AccessRecord {
        const actual_count = if (count > self.max_log_size) self.max_log_size else count;
        if (self.access_count < actual_count) {
            return self.access_log[0..self.access_count];
        }
        return self.access_log[0..actual_count];
    }
    
    /// Get access statistics
    pub fn getStatistics(self: *const MemoryAccessInstrumentation) struct {
        total_accesses: u64,
        successful_accesses: u64,
        failed_accesses: u64,
        fault_rate: f64,
    } {
        const successful = self.access_count - self.fault_count;
        const fault_rate = if (self.access_count > 0)
            @as(f64, @floatFromInt(self.fault_count)) / @as(f64, @floatFromInt(self.access_count))
        else
            0.0;
        
        return .{
            .total_accesses = self.access_count,
            .successful_accesses = successful,
            .failed_accesses = self.fault_count,
            .fault_rate = fault_rate,
        };
    }
    
    /// Detect patterns in recent faults
    pub fn analyzeFaultPatterns(self: *const MemoryAccessInstrumentation) struct {
        sign_extension_faults: u64,
        stack_corruption_faults: u64,
        unmapped_faults: u64,
        permission_faults: u64,
    } {
        var sign_ext: u64 = 0;
        var stack_corr: u64 = 0;
        var unmapped: u64 = 0;
        var permission: u64 = 0;
        
        const count = @min(self.access_count, self.max_log_size);
        for (self.access_log[0..count]) |access| {
            if (!access.successful) {
                if (access.error_type) |err| {
                    if (std.mem.eql(u8, err, "sign_extension_bug")) sign_ext += 1;
                    if (std.mem.eql(u8, err, "unmapped")) unmapped += 1;
                    if (std.mem.eql(u8, err, "permission_denied")) permission += 1;
                    if (std.mem.eql(u8, err, "stack_corruption")) stack_corr += 1;
                }
            }
        }
        
        return .{
            .sign_extension_faults = sign_ext,
            .stack_corruption_faults = stack_corr,
            .unmapped_faults = unmapped,
            .permission_faults = permission,
        };
    }
};

/// Combined memory access guard
pub const MemoryAccessGuard = struct {
    validator: AddressValidation,
    instrumentation: MemoryAccessInstrumentation,
    
    pub fn init(max_log_size: usize) MemoryAccessGuard {
        return .{
            .validator = AddressValidation.init(),
            .instrumentation = MemoryAccessInstrumentation.init(max_log_size),
        };
    }
    
    /// Comprehensive memory access check
    pub fn checkMemoryAccess(self: *MemoryAccessGuard, rip: u64, address: u64, size: u64, is_write: bool, is_execute: bool) !void {
        // Check for sign-extension bugs
        if (SignExtensionAuditor.detectSignExtensionBug(address)) {
            try self.instrumentation.recordAccess(
                rip, address, size, is_write, is_execute, false,
                "sign_extension_bug"
            );
            return error.SignExtensionBug;
        }
        
        // Check address validity
        if (!self.validator.isValidAddressRange(address, size)) {
            try self.instrumentation.recordAccess(
                rip, address, size, is_write, is_execute, false,
                "invalid_address"
            );
            return error.InvalidAddress;
        }
        
        // Check access permissions
        if (!self.validator.isValidForAccessType(address, is_write, is_execute)) {
            try self.instrumentation.recordAccess(
                rip, address, size, is_write, is_execute, false,
                "permission_denied"
            );
            return error.PermissionDenied;
        }
        
        // Access is valid
        try self.instrumentation.recordAccess(
            rip, address, size, is_write, is_execute, true, null
        );
    }
    
    /// Stack-relative access check
    pub fn checkStackAccess(self: *MemoryAccessGuard, rip: u64, address: u64, size: u64, stack_pointer: u64, max_stack_offset: u64) !void {
        if (!self.validator.validateStackAccess(address, stack_pointer, max_stack_offset)) {
            try self.instrumentation.recordAccess(
                rip, address, size, false, false, false,
                "stack_corruption"
            );
            return error.StackCorruption;
        }
        
        try self.instrumentation.recordAccess(
            rip, address, size, false, false, true, null
        );
    }
};

test "sign extension detection" {
    // Test case: address 0xffffffffffffffe8 (32-bit 0xffffffe8 sign-extended)
    const bad_addr: u64 = 0xffffffffffffffe8;
    try std.testing.expect(SignExtensionAuditor.detectSignExtensionBug(bad_addr));
    
    const pattern = SignExtensionAuditor.getSignExtensionPattern(bad_addr);
    try std.testing.expectEqual(SignExtensionAuditor.Pattern.likely_32bit_sign_extend, pattern);
    
    // Valid address should not trigger detection
    const good_addr: u64 = 0x1000;
    try std.testing.expect(!SignExtensionAuditor.detectSignExtensionBug(good_addr));
}

test "address validation basic functionality" {
    var validator = AddressValidation.init();
    
    try validator.addRegion(0x1000, 0x1000, "test_region", true, false);
    
    try std.testing.expect(validator.isValidAddress(0x1000));
    try std.testing.expect(validator.isValidAddress(0x1FFF));
    try std.testing.expect(!validator.isValidAddress(0x2000));
    
    try std.testing.expect(validator.isValidAddressRange(0x1000, 0x100));
    try std.testing.expect(!validator.isValidAddressRange(0x1F00, 0x200));
}

test "memory access instrumentation" {
    var instrumentation = MemoryAccessInstrumentation.init(100);
    
    try instrumentation.recordAccess(0x1000, 0x2000, 8, false, false, true, null);
    try instrumentation.recordAccess(0x1000, 0xffffffffffffffe8, 8, false, false, false, "sign_extension_bug");
    
    const stats = instrumentation.getStatistics();
    try std.testing.expectEqual(@as(u64, 2), stats.total_accesses);
    try std.testing.expectEqual(@as(u64, 1), stats.failed_accesses);
    
    const patterns = instrumentation.analyzeFaultPatterns();
    try std.testing.expectEqual(@as(u64, 1), patterns.sign_extension_faults);
}

test "comprehensive memory access guard" {
    var guard = MemoryAccessGuard.init(100);
    
    try guard.validator.addRegion(0x1000, 0x1000, "test", true, false);
    
    // Valid access should succeed
    try guard.checkMemoryAccess(0x1000, 0x1000, 8, false, false);
    
    // Invalid address should fail
    const result = guard.checkMemoryAccess(0x1000, 0x3000, 8, false, false);
    try std.testing.expectError(error.InvalidAddress, result);
    
    // Sign-extension bug should be detected
    const sign_ext_result = guard.checkMemoryAccess(0x1000, 0xffffffffffffffe8, 8, false, false);
    try std.testing.expectError(error.SignExtensionBug, sign_ext_result);
}
