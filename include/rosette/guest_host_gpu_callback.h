/*
 * Rosette/Xenia host GPU callback ABI.
 *
 * This is a proof-bearing, host-only seam.  Xenia remains responsible for
 * creating and invoking its callback trampoline.  Rosette only answers
 * whether that host action is permitted for the supplied state; this ABI can
 * never certify guest callback registration, PM4, ring, VdSwap, or output.
 */
#ifndef ROSETTE_XENIA_HOST_GPU_CALLBACK_H_
#define ROSETTE_XENIA_HOST_GPU_CALLBACK_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ROSETTE_XENIA_HOST_GPU_CALLBACK_SCHEMA 1u
#define ROSETTE_XENIA_HOST_GPU_CALLBACK_ABI 0x00010000u

enum rosette_xenia_host_gpu_callback_state_flag {
  ROSETTE_XENIA_HOST_GPU_CALLBACK_MODULE_PRESENT = 1u << 0,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_ENTRY_RESOLVED = 1u << 1,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_LOAD_IDLE = 1u << 2,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_GRAPHICS_READY = 1u << 3,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_COMMAND_PROCESSOR_READY = 1u << 4,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_GUEST_MAIN_RUNNING = 1u << 5,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_GUEST_CALLBACK_MISSING = 1u << 6,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_HOST_CALLBACK_MISSING = 1u << 7,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_RING_READY = 1u << 8,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_RING_NOT_READY = 1u << 9,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_BOOTSTRAP_ACTIVITY_SEEN = 1u << 10,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_BOOTSTRAP_ACTIVITY_ABSENT = 1u << 11,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_CADENCE_READY = 1u << 12,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_GUEST_MAIN_NOT_RUNNING = 1u << 13,
};

enum rosette_xenia_host_gpu_callback_action {
  ROSETTE_XENIA_HOST_GPU_CALLBACK_INSTALL_HOST_INTERRUPT_CALLBACK = 1u << 0,
};

typedef enum rosette_xenia_host_gpu_callback_decision {
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REFUSE = 0,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_ALLOW = 1,
} rosette_xenia_host_gpu_callback_decision_t;

typedef enum rosette_xenia_host_gpu_callback_reason {
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_NONE = 0,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_PROVIDER_DISABLED = 1,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_HOST_CONTROL_REQUIRED = 2,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_MALFORMED_REQUEST = 3,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_MODULE_MISSING = 4,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_ENTRY_UNRESOLVED = 5,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_LOAD_INFLIGHT = 6,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_GRAPHICS_NOT_READY = 7,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_COMMAND_PROCESSOR_NOT_READY = 8,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_GUEST_MAIN_NOT_RUNNING = 9,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_GUEST_CALLBACK_STATE_UNKNOWN = 10,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_GUEST_CALLBACK_PRESENT = 11,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_HOST_CALLBACK_STATE_UNKNOWN = 12,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_HOST_CALLBACK_PRESENT = 13,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_RING_STATE_UNKNOWN = 14,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_BOOTSTRAP_ACTIVITY_UNKNOWN = 15,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_CADENCE_NOT_READY = 16,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_REASON_NO_ACTIONABLE_CALLBACK = 17,
} rosette_xenia_host_gpu_callback_reason_t;

typedef enum rosette_xenia_host_gpu_callback_apply_status {
  ROSETTE_XENIA_HOST_GPU_CALLBACK_NOT_APPLIED = 0,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_APPLIED = 1,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_PARTIALLY_APPLIED = 2,
  ROSETTE_XENIA_HOST_GPU_CALLBACK_FAILED = 3,
} rosette_xenia_host_gpu_callback_apply_status_t;

/* The callback fields are opaque Xenia callback tokens, never host pointers. */
typedef struct rosette_xenia_host_gpu_callback_request {
  uint16_t size;
  uint16_t schema;
  uint32_t title_id;
  uint32_t entry_point;
  uint32_t state_flags;
  uint32_t guest_callback_token;
  uint32_t host_callback_token;
  uint32_t reserved;
  uint64_t guest_step;
  uint64_t vblank_id;
  uint64_t since_first_vblank_ms;
} rosette_xenia_host_gpu_callback_request_t;

typedef struct rosette_xenia_host_gpu_callback_response {
  uint16_t size;
  uint16_t schema;
  uint8_t decision;
  uint8_t reserved0;
  uint16_t reason;
  uint32_t actions;
  uint64_t proof_mask;
  uint64_t authorization_id;
} rosette_xenia_host_gpu_callback_response_t;

#if defined(__cplusplus)
static_assert(sizeof(rosette_xenia_host_gpu_callback_request_t) == 56,
              "host GPU callback request ABI drift");
static_assert(sizeof(rosette_xenia_host_gpu_callback_response_t) == 32,
              "host GPU callback response ABI drift");
#else
_Static_assert(sizeof(rosette_xenia_host_gpu_callback_request_t) == 56,
               "host GPU callback request ABI drift");
_Static_assert(sizeof(rosette_xenia_host_gpu_callback_response_t) == 32,
               "host GPU callback response ABI drift");
#endif

uint32_t rosette_xenia_host_gpu_callback_abi_version(void);
uint16_t rosette_xenia_host_gpu_callback_schema_version(void);
int32_t rosette_xenia_host_gpu_callback_query(
    const rosette_xenia_host_gpu_callback_request_t* request,
    rosette_xenia_host_gpu_callback_response_t* response);
int32_t rosette_xenia_host_gpu_callback_report(
    const rosette_xenia_host_gpu_callback_request_t* request,
    const rosette_xenia_host_gpu_callback_response_t* response,
    uint32_t applied_actions,
    uint8_t status);

#ifdef __cplusplus
}
#endif

#endif /* ROSETTE_XENIA_HOST_GPU_CALLBACK_H_ */
