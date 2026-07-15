The current version of Zig we are using to make Rosette happen is 0.16, given that this is the most current version. 

``` Makefile

ZIG_VERSION ?= 0.16.0

ZIG_CACHE_DIR ?= build/.zig-cache

ZIG_GLOBAL_CACHE_DIR ?= build/.zig-cache/global

ZIG_BUILD_ENV := ZIG_LOCAL_CACHE_DIR=$(ZIG_CACHE_DIR) ZIG_GLOBAL_CACHE_DIR=$(ZIG_GLOBAL_CACHE_DIR)

ZIG_LIB := zig-out/lib/librosette_zig.a
```

We use Rosette's 'build' folder to store all of the cache and libs that are required to make Rosette run
