// CPU-only extraction harness. Never creates a GPU device, pipeline or queue.
#include <cstdio>
#include <csignal>
#include <execinfo.h>
#include <unistd.h>
#include <fstream>
#include <iterator>
#include "xenia/gpu/spirv_shader_translator.h"

int main(int argc, char** argv) {
  auto trap = +[](int signal) {
    void* trace[32];
    const int count = backtrace(trace, 32);
    backtrace_symbols_fd(trace, count, STDERR_FILENO);
    _exit(128 + signal);
  };
  std::signal(SIGTRAP, trap);
  std::signal(SIGABRT, trap);
  if (argc != 7) {
    std::fprintf(stderr, "Usage: iso_shader_translate vs|ps input.ucode output.spv feature_mask storage_range spirv_version\n");
    return 2;
  }
  const std::string stage(argv[1]);
  if (stage != "vs" && stage != "ps") return 2;
  std::ifstream in(argv[2], std::ios::binary);
  std::vector<char> bytes((std::istreambuf_iterator<char>(in)), {});
  if (!in || bytes.size() < 12 || bytes.size() > (1 << 20) || bytes.size() % 12) {
    std::fprintf(stderr, "Invalid shader microcode length\n"); return 3;
  }
  std::vector<uint32_t> words(bytes.size() / 4);
  std::memcpy(words.data(), bytes.data(), bytes.size());
  for (auto& w : words) w = xe::byte_swap(w);
  // Validate instruction extents before Xenia's analyzer reads EXEC clauses.
  uint32_t bound = uint32_t(words.size() / 3);
  for (uint32_t i = 0; i < bound; ++i) {
    xe::gpu::ucode::ControlFlowInstruction cf[2];
    xe::gpu::ucode::UnpackControlFlowInstructions(words.data() + i * 3, cf);
    for (auto& c : cf) {
      if (xe::gpu::ucode::IsControlFlowOpcodeExec(c.opcode())) {
        if (c.exec.address() + c.exec.count() > words.size() / 3) {
          std::fprintf(stderr, "EXEC outside extracted code extent\n"); return 3;
        }
        bound = std::min(bound, c.exec.address());
        uint32_t sequence = c.exec.sequence();
        for (uint32_t j = 0; j < c.exec.count(); ++j, sequence >>= 2) {
          if (!(sequence & 1)) continue;
          const auto* fetch = reinterpret_cast<const xe::gpu::ucode::FetchInstruction*>(
              words.data() + (c.exec.address() + j) * 3);
          if (fetch->opcode() == xe::gpu::ucode::FetchOpcode::kVertexFetch &&
              !fetch->vertex_fetch().is_mini_fetch() &&
              !fetch->vertex_fetch().stride()) {
            std::fprintf(stderr, "Runtime vertex declaration required: zero-stride fetch at instruction %u\n",
                         c.exec.address() + j);
            return 6;
          }
        }
      }
    }
  }
  using namespace xe::gpu;
  Shader shader(stage == "vs" ? xenos::ShaderType::kVertex : xenos::ShaderType::kPixel,
                0, words.data(), words.size(), std::endian::little);
  xe::StringBuffer disasm;
  shader.AnalyzeUcode(disasm);
  // Physical-device capabilities queried offline. Runtime draw permutations
  // remain explicit test choices, not inferred from successful compilation.
  SpirvShaderTranslator::Features features(false);
  unsigned mask;
  try {
    mask = std::stoul(argv[4]);
    features.max_storage_buffer_range = std::stoul(argv[5]);
    features.spirv_version = std::stoul(argv[6]);
  } catch (...) { return 2; }
  bool* flags[] = {&features.full_draw_index_uint32, &features.vertex_pipeline_stores_and_atomics,
    &features.fragment_stores_and_atomics, &features.clip_distance, &features.cull_distance,
    &features.image_view_format_swizzle, &features.signed_zero_inf_nan_preserve_float32,
    &features.denorm_flush_to_zero_float32, &features.rounding_mode_rte_float32,
    &features.fragment_shader_sample_interlock, &features.demote_to_helper_invocation};
  for (unsigned i = 0; i < 11; ++i) *flags[i] = (mask & (1u << i)) != 0;
  SpirvShaderTranslator translator(features, false, false, true);
  SpirvShaderTranslator::Modification modification(stage == "vs"
      ? translator.GetDefaultVertexShaderModification(xenos::kMaxShaderTempRegisters)
      : translator.GetDefaultPixelShaderModification(xenos::kMaxShaderTempRegisters));
  // Preserve the guest's written interpolators; don't optimize the entire
  // vertex interface away just because this CPU harness has no paired draw.
  if (stage == "vs") modification.vertex.interpolator_mask = shader.writes_interpolators();
  else modification.pixel.interpolator_mask = 0xffff;
  auto* translation = shader.GetOrCreateTranslation(modification.value);
  translator.TranslateAnalyzedShader(*translation);
  const auto& output = translation->translated_binary();
  if (!translation->is_valid() || output.size() < 20 || output.size() % 4) {
    std::fprintf(stderr, "Xenia translation invalid\n"); return 4;
  }
  std::ofstream out(argv[3], std::ios::binary);
  out.write(reinterpret_cast<const char*>(output.data()), output.size());
  if (!out) return 5;
  std::printf("stage=%s modification=%016llx ucode_bytes=%zu spirv_bytes=%zu\n",
              stage.c_str(), (unsigned long long)modification.value, bytes.size(), output.size());
}
