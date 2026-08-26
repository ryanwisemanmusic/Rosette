/*
 * Optional Xenia-side adapter for the Rosette application framework.
 *
 * The bridge resolves Rosette's exported ABI lazily with dlsym.  When Xenia is
 * run normally, every method is a cheap no-op.  When it is hosted by the
 * Rosette Mach-O processor, the same calls become structured events and value
 * checks.  No Xenia object pointer crosses the ABI.
 */
#ifndef ROSETTE_XENIA_APPLICATION_BRIDGE_H_
#define ROSETTE_XENIA_APPLICATION_BRIDGE_H_

#include <stdint.h>
#include <mutex>
#include <string.h>

#if defined(__APPLE__)
#include <dlfcn.h>
#endif

#include "rosette/application_framework.h"

namespace xe::rosette {

class ApplicationBridge final {
 public:
  static ApplicationBridge& Get() {
    static ApplicationBridge bridge;
    return bridge;
  }

  bool available() {
    Resolve();
    return handle_ != nullptr && emit_ != nullptr;
  }

  void RegisterAdapter(const char* name, uint64_t capabilities) {
    Resolve();
    if (register_adapter_ == nullptr || handle_ == nullptr) return;
    register_adapter_(handle_, name != nullptr ? name : "xenia", capabilities);
  }

  void ObserveVdSwapEntered(uint64_t guest_step, uint64_t guest_rip,
                            uint32_t buffer_ptr, uint32_t fetch_ptr,
                            uint32_t frontbuffer_ptr) {
    Emit(ROSETTE_APPLICATION_FRAMEWORK_EVENT_VD_SWAP,
         ROSETTE_APPLICATION_FRAMEWORK_TRUTH_OBSERVED,
         ROSETTE_APPLICATION_FRAMEWORK_OWNER_XENIA_KERNEL,
         ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_VD_SWAP, guest_step, guest_rip,
         frontbuffer_ptr, buffer_ptr,
         fetch_ptr, "VdSwap", "VdSwap entry boundary reached");
  }

  void ObserveVdSwapEncoded(uint64_t guest_step, uint64_t guest_rip,
                            uint32_t physical_frontbuffer, uint32_t width,
                            uint32_t height, uint32_t dwords) {
    Emit(ROSETTE_APPLICATION_FRAMEWORK_EVENT_VD_SWAP,
         ROSETTE_APPLICATION_FRAMEWORK_TRUTH_OBSERVED,
         ROSETTE_APPLICATION_FRAMEWORK_OWNER_XENIA_KERNEL,
         ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_VD_SWAP, guest_step, guest_rip,
         physical_frontbuffer, width,
         (static_cast<uint64_t>(height) << 32) | dwords, "VdSwap-encoded",
         "guest-owned XE_SWAP payload encoded");
  }

  void ObservePm4Packet(uint64_t guest_step, uint64_t guest_rip,
                        uint32_t opcode, uint32_t count, uint32_t packet_id) {
    Emit(ROSETTE_APPLICATION_FRAMEWORK_EVENT_PM4_PACKET,
         ROSETTE_APPLICATION_FRAMEWORK_TRUTH_OBSERVED,
         ROSETTE_APPLICATION_FRAMEWORK_OWNER_XENIA_GPU,
         ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_PM4, guest_step, guest_rip,
         opcode, count, packet_id, "PM4", "PM4 packet consumed");
  }

  void ObserveIssueSwap(uint64_t guest_step, uint64_t guest_rip,
                        uint32_t frontbuffer_ptr, uint32_t width,
                        uint32_t height) {
    Emit(ROSETTE_APPLICATION_FRAMEWORK_EVENT_PRESENTATION,
         ROSETTE_APPLICATION_FRAMEWORK_TRUTH_OBSERVED,
         ROSETTE_APPLICATION_FRAMEWORK_OWNER_XENIA_PRESENTER,
         ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_PRESENTER, guest_step,
         guest_rip, frontbuffer_ptr, width, height, "IssueSwap",
         "native IssueSwap boundary reached");
  }

  void ObservePresenterOutcome(uint64_t guest_step, uint64_t guest_rip,
                               uint32_t frontbuffer_ptr, bool refresh_active,
                               uint64_t refresh_success_delta,
                               const char* detail) {
    Emit(ROSETTE_APPLICATION_FRAMEWORK_EVENT_PRESENTATION,
         ROSETTE_APPLICATION_FRAMEWORK_TRUTH_OBSERVED,
         ROSETTE_APPLICATION_FRAMEWORK_OWNER_XENIA_PRESENTER,
         ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_PRESENTER, guest_step,
         guest_rip, frontbuffer_ptr,
         refresh_active ? 1 : 0, refresh_success_delta, "RefreshGuestOutput",
         detail != nullptr ? detail : "presenter outcome observed");
  }

  bool CompareValue(uint64_t guest_step, uint64_t guest_rip, uint64_t subject,
                    uint64_t expected, uint64_t actual, uint64_t mask,
                    const char* name) {
    Resolve();
    if (compare_ == nullptr || handle_ == nullptr) return false;
    const uint8_t result = compare_(
        handle_, ROSETTE_APPLICATION_FRAMEWORK_OWNER_XENIA_GPU,
        ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_FRAMEWORK, subject, expected,
        actual, mask, guest_step, guest_rip,
                                    name != nullptr ? name : "boundary");
    return result == ROSETTE_APPLICATION_FRAMEWORK_EQ_MATCH ||
           result == ROSETTE_APPLICATION_FRAMEWORK_EQ_MASKED_MATCH ||
           result == ROSETTE_APPLICATION_FRAMEWORK_EQ_TOLERANCE_MATCH;
  }

  void ObserveControlTransfer(uint64_t guest_step, uint64_t thread_id,
                              uint64_t source, uint64_t target, bool taken,
                              const char* name) {
    Resolve();
    if (observe_control_transfer_ == nullptr || handle_ == nullptr) return;
    observe_control_transfer_(handle_, ROSETTE_APPLICATION_FRAMEWORK_OWNER_GUEST,
                              source, target, guest_step, thread_id,
                              taken ? 1 : 0,
                              name != nullptr ? name : "control-transfer");
  }

 private:
  using HandleFn = rosette_application_framework* (*)();
  using AbiVersionFn = uint32_t (*)();
  using SchemaVersionFn = uint16_t (*)();
  using RegisterAdapterFn = int32_t (*)(rosette_application_framework*,
                                       const char*, uint64_t);
  using EmitFn = int32_t (*)(rosette_application_framework*,
                             const rosette_application_framework_event_t*);
  using CompareFn = uint8_t (*)(rosette_application_framework*, uint8_t,
                                uint8_t, uint64_t, uint64_t, uint64_t,
                                uint64_t, uint64_t, uint64_t, const char*);
  using ObserveControlTransferFn = int32_t (*)(
      rosette_application_framework*, uint8_t, uint64_t, uint64_t, uint64_t,
      uint64_t, uint8_t, const char*);

  ApplicationBridge() = default;

  void Resolve() {
    std::call_once(resolve_once_, [this]() {
#if defined(__APPLE__)
    abi_version_ = reinterpret_cast<AbiVersionFn>(
        dlsym(RTLD_DEFAULT, "rosette_application_framework_abi_version"));
    schema_version_ = reinterpret_cast<SchemaVersionFn>(
        dlsym(RTLD_DEFAULT, "rosette_application_framework_schema_version"));
    handle_fn_ = reinterpret_cast<HandleFn>(
        dlsym(RTLD_DEFAULT, "rosette_application_framework_handle"));
    register_adapter_ = reinterpret_cast<RegisterAdapterFn>(dlsym(
        RTLD_DEFAULT, "rosette_application_framework_register_adapter"));
    emit_ = reinterpret_cast<EmitFn>(
        dlsym(RTLD_DEFAULT, "rosette_application_framework_emit"));
    compare_ = reinterpret_cast<CompareFn>(
        dlsym(RTLD_DEFAULT, "rosette_application_framework_compare"));
    observe_control_transfer_ = reinterpret_cast<ObserveControlTransferFn>(
        dlsym(RTLD_DEFAULT,
              "rosette_application_framework_observe_control_transfer"));
    const bool abi_compatible =
        abi_version_ != nullptr &&
        abi_version_() == ROSETTE_APPLICATION_FRAMEWORK_ABI;
    const bool schema_compatible =
        schema_version_ != nullptr &&
        schema_version_() == ROSETTE_APPLICATION_FRAMEWORK_SCHEMA;
    if (abi_compatible && schema_compatible && handle_fn_ != nullptr) {
      handle_ = handle_fn_();
    } else {
      handle_ = nullptr;
      emit_ = nullptr;
      compare_ = nullptr;
      observe_control_transfer_ = nullptr;
    }
#endif
    });
  }

  void Emit(uint8_t kind, uint8_t truth, uint8_t owner, uint8_t domain,
            uint64_t guest_step, uint64_t guest_rip, uint64_t subject,
            uint64_t actual, uint64_t auxiliary, const char* name,
            const char* detail) {
    Resolve();
    if (emit_ == nullptr || handle_ == nullptr) return;
    rosette_application_framework_event_t event{};
    event.size = sizeof(event);
    event.schema = ROSETTE_APPLICATION_FRAMEWORK_SCHEMA;
    event.kind = kind;
    event.truth = truth;
    event.owner = owner;
    event.domain = domain;
    event.value_kind = 1;
    event.guest_step = guest_step;
    event.guest_rip = guest_rip;
    event.subject = subject;
    event.actual = actual;
    event.auxiliary = auxiliary;
    if (name != nullptr) {
      strncpy(reinterpret_cast<char*>(event.name), name,
              sizeof(event.name) - 1);
    }
    if (detail != nullptr) {
      strncpy(reinterpret_cast<char*>(event.detail), detail,
              sizeof(event.detail) - 1);
    }
    emit_(handle_, &event);
  }

  std::once_flag resolve_once_;
  rosette_application_framework* handle_ = nullptr;
  HandleFn handle_fn_ = nullptr;
  AbiVersionFn abi_version_ = nullptr;
  SchemaVersionFn schema_version_ = nullptr;
  RegisterAdapterFn register_adapter_ = nullptr;
  EmitFn emit_ = nullptr;
  CompareFn compare_ = nullptr;
  ObserveControlTransferFn observe_control_transfer_ = nullptr;
};

}  // namespace xe::rosette

#endif /* ROSETTE_XENIA_APPLICATION_BRIDGE_H_ */
