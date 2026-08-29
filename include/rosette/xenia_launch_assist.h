/*
 * Rosette/Xenia launch-assist ABI.
 *
 * This is a proof-bearing host-startup seam, not a guest-control API. Rosette
 * can authorize a narrowly defined host operation after Xenia supplies every
 * required readiness fact; it cannot create guest execution or GPU evidence.
 */
#ifndef ROSETTE_XENIA_LAUNCH_ASSIST_H_
#define ROSETTE_XENIA_LAUNCH_ASSIST_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ROSETTE_XENIA_LAUNCH_ASSIST_SCHEMA 1u
#define ROSETTE_XENIA_LAUNCH_ASSIST_ABI 0x00010000u

enum rosette_xenia_launch_assist_state_flag {
  ROSETTE_XENIA_LAUNCH_ASSIST_MODULE_PRESENT = 1u << 0,
  ROSETTE_XENIA_LAUNCH_ASSIST_ENTRY_RESOLVED = 1u << 1,
  ROSETTE_XENIA_LAUNCH_ASSIST_LOAD_IDLE = 1u << 2,
  ROSETTE_XENIA_LAUNCH_ASSIST_GRAPHICS_READY = 1u << 3,
  ROSETTE_XENIA_LAUNCH_ASSIST_COMMAND_PROCESSOR_READY = 1u << 4,
  ROSETTE_XENIA_LAUNCH_ASSIST_METADATA_OPTIONAL = 1u << 5,
  ROSETTE_XENIA_LAUNCH_ASSIST_GUEST_MAIN_STARTED = 1u << 6,
  ROSETTE_XENIA_LAUNCH_ASSIST_GUEST_GPU_ACTIVITY = 1u << 7,
  ROSETTE_XENIA_LAUNCH_ASSIST_RING_READY = 1u << 8,
  ROSETTE_XENIA_LAUNCH_ASSIST_DISPATCH_WORKER_RUNNING = 1u << 9,
  ROSETTE_XENIA_LAUNCH_ASSIST_GUEST_MAIN_NOT_STARTED = 1u << 10,
  ROSETTE_XENIA_LAUNCH_ASSIST_GUEST_GPU_IDLE = 1u << 11,
  ROSETTE_XENIA_LAUNCH_ASSIST_RING_NOT_READY = 1u << 12,
  ROSETTE_XENIA_LAUNCH_ASSIST_DISPATCH_WORKER_NOT_RUNNING = 1u << 13,
};

enum rosette_xenia_launch_assist_action {
  ROSETTE_XENIA_LAUNCH_ASSIST_DEFER_OPTIONAL_TITLE_METADATA = 1u << 0,
  ROSETTE_XENIA_LAUNCH_ASSIST_START_DEFERRED_DISPATCH_WORKER = 1u << 1,
};

typedef enum rosette_xenia_launch_assist_decision {
  ROSETTE_XENIA_LAUNCH_ASSIST_REFUSE = 0,
  ROSETTE_XENIA_LAUNCH_ASSIST_ALLOW = 1,
} rosette_xenia_launch_assist_decision_t;

typedef enum rosette_xenia_launch_assist_reason {
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_NONE = 0,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_PROVIDER_DISABLED = 1,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_MALFORMED_REQUEST = 2,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_HOST_CONTROL_REQUIRED = 3,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_MODULE_MISSING = 4,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_ENTRY_UNRESOLVED = 5,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_LOAD_INFLIGHT = 6,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_GRAPHICS_NOT_READY = 7,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_COMMAND_PROCESSOR_NOT_READY = 8,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_METADATA_REQUIRED = 9,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_GUEST_ALREADY_STARTED = 10,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_GUEST_GPU_ACTIVITY = 11,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_RING_ALREADY_READY = 12,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_GUEST_STATE_UNKNOWN = 13,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_DISPATCH_WORKER_STATE_UNKNOWN = 14,
  ROSETTE_XENIA_LAUNCH_ASSIST_REASON_NO_ACTIONABLE_ASSIST = 15,
} rosette_xenia_launch_assist_reason_t;

typedef enum rosette_xenia_launch_assist_apply_status {
  ROSETTE_XENIA_LAUNCH_ASSIST_NOT_APPLIED = 0,
  ROSETTE_XENIA_LAUNCH_ASSIST_APPLIED = 1,
  ROSETTE_XENIA_LAUNCH_ASSIST_PARTIALLY_APPLIED = 2,
  ROSETTE_XENIA_LAUNCH_ASSIST_FAILED = 3,
} rosette_xenia_launch_assist_apply_status_t;

typedef struct rosette_xenia_launch_assist_request {
  uint16_t size;
  uint16_t schema;
  uint32_t title_id;
  uint32_t entry_point;
  uint32_t state_flags;
  uint32_t reserved;
  uint64_t guest_step;
} rosette_xenia_launch_assist_request_t;

typedef struct rosette_xenia_launch_assist_response {
  uint16_t size;
  uint16_t schema;
  uint8_t decision;
  uint8_t reserved0;
  uint16_t reason;
  uint32_t actions;
  uint64_t proof_mask;
} rosette_xenia_launch_assist_response_t;

uint32_t rosette_xenia_launch_assist_abi_version(void);
uint16_t rosette_xenia_launch_assist_schema_version(void);
int32_t rosette_xenia_launch_assist_query(
    const rosette_xenia_launch_assist_request_t* request,
    rosette_xenia_launch_assist_response_t* response);
int32_t rosette_xenia_launch_assist_report(
    const rosette_xenia_launch_assist_request_t* request,
    const rosette_xenia_launch_assist_response_t* response,
    uint32_t applied_actions,
    uint8_t status);

#ifdef __cplusplus
}
#endif

#endif /* ROSETTE_XENIA_LAUNCH_ASSIST_H_ */
