/*
 * Rosette application-framework ABI.
 *
 * This header is deliberately pointer-light: events and requests contain
 * fixed-width values only, so an adapter can be compiled into Xenia or loaded
 * from a separate dylib without sharing Zig/C++ ownership or allocator state.
 */
#ifndef ROSETTE_APPLICATION_FRAMEWORK_H_
#define ROSETTE_APPLICATION_FRAMEWORK_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ROSETTE_APPLICATION_FRAMEWORK_SCHEMA 1u
#define ROSETTE_APPLICATION_FRAMEWORK_ABI 0x00010000u
#define ROSETTE_APPLICATION_FRAMEWORK_NAME_BYTES 48u
#define ROSETTE_APPLICATION_FRAMEWORK_DETAIL_BYTES 96u

typedef enum rosette_application_framework_mode {
  ROSETTE_APPLICATION_FRAMEWORK_MODE_DISABLED = 0,
  ROSETTE_APPLICATION_FRAMEWORK_MODE_OBSERVE_ONLY = 1,
  ROSETTE_APPLICATION_FRAMEWORK_MODE_HOST_CONTROL = 2,
  ROSETTE_APPLICATION_FRAMEWORK_MODE_EXPERIMENTAL_CONTROL = 3,
} rosette_application_framework_mode_t;

/* Capability values are stable bit positions, not an implementation detail of
 * the current Zig enum order. */
#define ROSETTE_APPLICATION_FRAMEWORK_CAP_OBSERVE_EVENTS (UINT64_C(1) << 0)
#define ROSETTE_APPLICATION_FRAMEWORK_CAP_INSPECT_CONTROL_FLOW (UINT64_C(1) << 1)
#define ROSETTE_APPLICATION_FRAMEWORK_CAP_INSPECT_MEMORY (UINT64_C(1) << 2)
#define ROSETTE_APPLICATION_FRAMEWORK_CAP_INSPECT_GRAPHICS (UINT64_C(1) << 3)
#define ROSETTE_APPLICATION_FRAMEWORK_CAP_INSPECT_BACKEND (UINT64_C(1) << 4)
#define ROSETTE_APPLICATION_FRAMEWORK_CAP_CONTROL_SCHEDULER (UINT64_C(1) << 5)
#define ROSETTE_APPLICATION_FRAMEWORK_CAP_CONTROL_HOST_PRESENTER (UINT64_C(1) << 6)
#define ROSETTE_APPLICATION_FRAMEWORK_CAP_INVOKE_GUEST_API (UINT64_C(1) << 7)
#define ROSETTE_APPLICATION_FRAMEWORK_CAP_MUTATE_GUEST_MEMORY (UINT64_C(1) << 8)
#define ROSETTE_APPLICATION_FRAMEWORK_CAP_MUTATE_HOST_STATE (UINT64_C(1) << 9)

typedef enum rosette_application_framework_owner {
  ROSETTE_APPLICATION_FRAMEWORK_OWNER_UNKNOWN = 0,
  ROSETTE_APPLICATION_FRAMEWORK_OWNER_ROSETTE = 1,
  ROSETTE_APPLICATION_FRAMEWORK_OWNER_GUEST = 2,
  ROSETTE_APPLICATION_FRAMEWORK_OWNER_XENIA_KERNEL = 3,
  ROSETTE_APPLICATION_FRAMEWORK_OWNER_XENIA_GPU = 4,
  ROSETTE_APPLICATION_FRAMEWORK_OWNER_XENIA_PRESENTER = 5,
  ROSETTE_APPLICATION_FRAMEWORK_OWNER_HOST_FRAMEWORK = 6,
  ROSETTE_APPLICATION_FRAMEWORK_OWNER_EXTERNAL_ADAPTER = 7,
} rosette_application_framework_owner_t;

typedef enum rosette_application_framework_domain {
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_UNKNOWN = 0,
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_PROCESS = 1,
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_CONTROL_FLOW = 2,
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_SCHEDULER = 3,
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_MEMORY = 4,
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_KERNEL = 5,
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_PM4 = 6,
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_VD_SWAP = 7,
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_GRAPHICS_BACKEND = 8,
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_PRESENTER = 9,
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_EQUIVALENCE = 10,
  ROSETTE_APPLICATION_FRAMEWORK_DOMAIN_FRAMEWORK = 11,
} rosette_application_framework_domain_t;

typedef enum rosette_application_framework_event_kind {
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_PROCESS = 0,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_FUNCTION_ENTER = 1,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_FUNCTION_EXIT = 2,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_CONTROL_TRANSFER = 3,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_BRANCH = 4,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_STATE_OBSERVATION = 5,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_STATE_WRITE = 6,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_SCHEDULER = 7,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_WAIT = 8,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_SIGNAL = 9,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_MEMORY = 10,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_PM4_PACKET = 11,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_VD_SWAP = 12,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_BACKEND_CALL = 13,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_PRESENTATION = 14,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_EQUIVALENCE = 15,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_COMMAND_REQUEST = 16,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_COMMAND_RESULT = 17,
  ROSETTE_APPLICATION_FRAMEWORK_EVENT_FAULT = 18,
} rosette_application_framework_event_kind_t;

typedef enum rosette_application_framework_truth {
  ROSETTE_APPLICATION_FRAMEWORK_TRUTH_OBSERVED = 0,
  ROSETTE_APPLICATION_FRAMEWORK_TRUTH_REQUESTED = 1,
  ROSETTE_APPLICATION_FRAMEWORK_TRUTH_APPLIED = 2,
  ROSETTE_APPLICATION_FRAMEWORK_TRUTH_REJECTED = 3,
  ROSETTE_APPLICATION_FRAMEWORK_TRUTH_INFERRED = 4,
} rosette_application_framework_truth_t;

typedef enum rosette_application_framework_equivalence {
  ROSETTE_APPLICATION_FRAMEWORK_EQ_NOT_CHECKED = 0,
  ROSETTE_APPLICATION_FRAMEWORK_EQ_MATCH = 1,
  ROSETTE_APPLICATION_FRAMEWORK_EQ_MASKED_MATCH = 2,
  ROSETTE_APPLICATION_FRAMEWORK_EQ_TOLERANCE_MATCH = 3,
  ROSETTE_APPLICATION_FRAMEWORK_EQ_MISMATCH = 4,
  ROSETTE_APPLICATION_FRAMEWORK_EQ_UNAVAILABLE = 5,
} rosette_application_framework_equivalence_t;

typedef enum rosette_application_framework_command {
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_SNAPSHOT = 0,
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_ENABLE_TRACE = 1,
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_DISABLE_TRACE = 2,
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_PAUSE_GUEST = 3,
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_RESUME_GUEST = 4,
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_DRAIN_GPU_INTERRUPTS = 5,
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_REFRESH_OUTPUT = 6,
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_SET_BREAKPOINT = 7,
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_INSPECT_GUEST_MEMORY = 8,
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_INVOKE_GUEST_API = 9,
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_WRITE_GUEST_MEMORY = 10,
  ROSETTE_APPLICATION_FRAMEWORK_COMMAND_WRITE_HOST_STATE = 11,
} rosette_application_framework_command_t;

typedef enum rosette_application_framework_request_status {
  ROSETTE_APPLICATION_FRAMEWORK_REQUEST_INVALID = 0,
  ROSETTE_APPLICATION_FRAMEWORK_REQUEST_DISABLED = 1,
  ROSETTE_APPLICATION_FRAMEWORK_REQUEST_QUEUED = 2,
  ROSETTE_APPLICATION_FRAMEWORK_REQUEST_APPLIED = 3,
  ROSETTE_APPLICATION_FRAMEWORK_REQUEST_DENIED = 4,
  ROSETTE_APPLICATION_FRAMEWORK_REQUEST_UNSUPPORTED = 5,
  ROSETTE_APPLICATION_FRAMEWORK_REQUEST_NOT_READY = 6,
} rosette_application_framework_request_status_t;

typedef struct rosette_application_framework rosette_application_framework;

typedef struct rosette_application_framework_config {
  uint16_t size;
  uint16_t schema;
  uint8_t mode; /* 0 disabled, 1 observe-only, 2 host-control, 3 experimental */
  uint8_t reserved0;
  uint16_t reserved1;
  uint64_t capabilities;
  uint64_t application_id;
  uint8_t trace_control_flow;
  uint8_t trace_memory;
  uint8_t trace_graphics;
  uint8_t reserved2;
  uint32_t max_events;
} rosette_application_framework_config_t;

typedef struct rosette_application_framework_request {
  uint16_t size;
  uint16_t schema;
  uint8_t command;
  uint8_t reserved0;
  uint16_t reserved1;
  uint64_t request_id;
  uint64_t guest_step;
  uint64_t subject;
  uint64_t argument0;
  uint64_t argument1;
  uint64_t argument2;
  uint64_t name_hash;
} rosette_application_framework_request_t;

typedef struct rosette_application_framework_request_result {
  uint16_t size;
  uint16_t schema;
  uint8_t status;
  uint8_t reserved0;
  uint16_t reserved1;
  uint64_t request_id;
  uint64_t reason_code;
} rosette_application_framework_request_result_t;

typedef struct rosette_application_framework_event {
  uint16_t size;
  uint16_t schema;
  uint8_t kind;
  uint8_t truth;
  uint8_t owner;
  uint8_t domain;
  uint8_t value_kind;
  uint8_t equivalence;
  uint16_t reserved0;
  uint64_t sequence;
  uint64_t guest_step;
  uint64_t thread_id;
  uint64_t guest_rip;
  uint64_t host_pc;
  uint64_t subject;
  uint64_t expected;
  uint64_t actual;
  uint64_t mask;
  uint64_t auxiliary;
  uint64_t name_hash;
  uint8_t name[ROSETTE_APPLICATION_FRAMEWORK_NAME_BYTES];
  uint8_t detail[ROSETTE_APPLICATION_FRAMEWORK_DETAIL_BYTES];
} rosette_application_framework_event_t;

typedef struct rosette_application_framework_snapshot {
  uint16_t size;
  uint16_t schema;
  uint8_t mode;
  uint8_t reserved0;
  uint16_t reserved1;
  uint64_t sequence;
  uint64_t events_retained;
  uint64_t events_total;
  uint64_t events_dropped;
  uint64_t requests_total;
  uint64_t requests_queued;
  uint64_t requests_applied;
  uint64_t requests_denied;
  uint64_t equivalence_checks;
  uint64_t equivalence_matches;
  uint64_t equivalence_mismatches;
  uint64_t last_guest_step;
  uint64_t last_guest_rip;
  uint64_t application_id;
} rosette_application_framework_snapshot_t;

uint32_t rosette_application_framework_abi_version(void);
uint16_t rosette_application_framework_schema_version(void);
rosette_application_framework *rosette_application_framework_handle(void);
int32_t rosette_application_framework_configure(
    rosette_application_framework *framework,
    const rosette_application_framework_config_t *config);
int32_t rosette_application_framework_register_adapter(
    rosette_application_framework *framework, const char *name,
    uint64_t capabilities);
int32_t rosette_application_framework_emit(
    rosette_application_framework *framework,
    const rosette_application_framework_event_t *event);
int32_t rosette_application_framework_observe_function_enter(
    rosette_application_framework *framework, uint8_t owner, uint8_t domain,
    const char *name, uint64_t guest_step, uint64_t guest_rip,
    uint64_t thread_id, uint64_t host_pc);
int32_t rosette_application_framework_observe_function_exit(
    rosette_application_framework *framework, uint8_t owner, uint8_t domain,
    const char *name, uint64_t guest_step, uint64_t guest_rip,
    uint64_t thread_id, uint64_t result);
int32_t rosette_application_framework_observe_control_transfer(
    rosette_application_framework *framework, uint8_t owner, uint64_t source,
    uint64_t target, uint64_t guest_step, uint64_t thread_id, uint8_t taken,
    const char *name);
int32_t rosette_application_framework_observe_value(
    rosette_application_framework *framework, uint8_t owner, uint8_t domain,
    uint64_t subject, uint64_t actual, uint64_t guest_step, uint64_t guest_rip,
    const char *name, const char *detail);
uint8_t rosette_application_framework_compare(
    rosette_application_framework *framework, uint8_t owner, uint8_t domain,
    uint64_t subject, uint64_t expected, uint64_t actual, uint64_t mask,
    uint64_t guest_step, uint64_t guest_rip, const char *name);
int32_t rosette_application_framework_request(
    rosette_application_framework *framework,
    const rosette_application_framework_request_t *request,
    rosette_application_framework_request_result_t *result);
int32_t rosette_application_framework_take_request(
    rosette_application_framework *framework,
    rosette_application_framework_request_t *request);
int32_t rosette_application_framework_complete_request(
    rosette_application_framework *framework, uint64_t request_id,
    uint8_t status, uint64_t reason_code);
int32_t rosette_application_framework_read_event(
    rosette_application_framework *framework, uint64_t ordinal,
    rosette_application_framework_event_t *event);
int32_t rosette_application_framework_snapshot(
    rosette_application_framework *framework,
    rosette_application_framework_snapshot_t *snapshot);

#ifdef __cplusplus
}
#endif

#endif /* ROSETTE_APPLICATION_FRAMEWORK_H_ */
