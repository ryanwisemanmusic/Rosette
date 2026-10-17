// Standalone CPU harness: keep Xenia's declared defaults, omit its app registry.
// No shader instructions or translation routines are replaced.
#pragma once
#include <filesystem>
#include <string>
#define DECLARE_bool(name) namespace cvars { extern bool name; }
#define DECLARE_path(name) namespace cvars { extern std::filesystem::path name; }
#define DECLARE_string(name) namespace cvars { extern std::string name; }
#define DECLARE_int32(name) namespace cvars { extern int32_t name; }
#define DECLARE_uint32(name) namespace cvars { extern uint32_t name; }
#define DECLARE_uint64(name) namespace cvars { extern uint64_t name; }
#define DECLARE_int64(name) namespace cvars { extern int64_t name; }
#define DECLARE_double(name) namespace cvars { extern double name; }
#define DEFINE_bool(name, value, ...) namespace cvars { bool name = value; }
