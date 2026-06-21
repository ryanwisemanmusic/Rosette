const runtime = @import("runtime/clr_runtime.zig");

pub const CLRRuntime = runtime.CLRRuntime;
pub const initRuntime = runtime.initRuntime;
pub const setAssemblyData = runtime.setAssemblyData;
pub const deinitRuntime = runtime.deinitRuntime;
pub const getRuntime = runtime.getRuntime;
