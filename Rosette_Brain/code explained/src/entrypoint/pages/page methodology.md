The entrypoint of this file is to define the sizes of pages I've currently worked in. Which are 4 different page sizes. I know there are other potential page sizes, but this is the current block that shouldn't need updating unless you feel like you are hitting a new roadblock a complaint that you aren't abiding by a certain page size: 
```root.zig
pub const PAGE_1K: u64 = 1024;

pub const PAGE_4K: u64 = 4096;

pub const PAGE_16K: u64 = 16384;

pub const PAGE_2M: u64 = 2 * 1024 * 1024;

pub const PAGE_4M: u64 = 4 * 1024 * 1024;
```

Windows default page size is 4kb whilst on the ARM64 chips, they decided to go to 16kb pages. This means that you can load far more pages to make up the total size of pages for completion. 

```root.zig
pub const NATIVE_PAGE_SHIFT: u6 = switch (builtin.target.cpu.arch) {

// 2^12 = 4096: 4k

.aarch64 => 14,

// 2^14 = 16384: 16k

else => 12,

};
```

On this, you want to ensure that you have the ability to have four 4K pages in slots in the 16k pages, which means you'll be able to process Windows code much quicker since more data you can access is stored in these larger default pages. 
```root.zig
pub const SUB_SLOT_SIZE: u64 = PAGE_4K;
pub const SUB_SLOTS_PER_NATIVE: u4 = @intCast(NATIVE_PAGE_SIZE / SUB_SLOT_SIZE);
```

NOTE: On the above, if I were to ever do a reversal of this for Windows, to get macOS code working, that would mean Windows would deal with 4x the number of pages. I'd have to recheck the cache implementation, but that would be a difficult problem to deal with

