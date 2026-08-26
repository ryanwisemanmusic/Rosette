#include "../../include/rosette/application_framework.h"

typedef struct {
  uint32_t (*abi_version)(void);
  uint16_t (*schema_version)(void);
  rosette_application_framework* (*handle)(void);
  int32_t (*configure)(rosette_application_framework*,
                       const rosette_application_framework_config_t*);
  int32_t (*register_adapter)(rosette_application_framework*, const char*,
                              uint64_t);
  int32_t (*emit)(rosette_application_framework*,
                  const rosette_application_framework_event_t*);
  int32_t (*observe_function_enter)(rosette_application_framework*, uint8_t,
                                    uint8_t, const char*, uint64_t, uint64_t,
                                    uint64_t, uint64_t);
  int32_t (*observe_function_exit)(rosette_application_framework*, uint8_t,
                                   uint8_t, const char*, uint64_t, uint64_t,
                                   uint64_t, uint64_t);
  int32_t (*observe_control_transfer)(rosette_application_framework*, uint8_t,
                                      uint64_t, uint64_t, uint64_t, uint64_t,
                                      uint8_t, const char*);
  int32_t (*observe_value)(rosette_application_framework*, uint8_t, uint8_t,
                           uint64_t, uint64_t, uint64_t, uint64_t, const char*,
                           const char*);
  uint8_t (*compare)(rosette_application_framework*, uint8_t, uint8_t,
                     uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t,
                     const char*);
  int32_t (*request)(rosette_application_framework*,
                     const rosette_application_framework_request_t*,
                     rosette_application_framework_request_result_t*);
  int32_t (*take_request)(rosette_application_framework*,
                          rosette_application_framework_request_t*);
  int32_t (*complete_request)(rosette_application_framework*, uint64_t, uint8_t,
                              uint64_t);
  int32_t (*read_event)(rosette_application_framework*, uint64_t,
                        rosette_application_framework_event_t*);
  int32_t (*snapshot)(rosette_application_framework*,
                      rosette_application_framework_snapshot_t*);
} rosette_application_framework_exports_t;

/* ReleaseFast dead-strips unreferenced exported functions unless a retained
 * relocation keeps them live. Xenia resolves these exact names with dlsym, so
 * this anchor is part of the ABI rather than an optional optimization detail.
 */
__attribute__((used, retain)) static const rosette_application_framework_exports_t
    rosette_application_framework_exports_anchor = {
        rosette_application_framework_abi_version,
        rosette_application_framework_schema_version,
        rosette_application_framework_handle,
        rosette_application_framework_configure,
        rosette_application_framework_register_adapter,
        rosette_application_framework_emit,
        rosette_application_framework_observe_function_enter,
        rosette_application_framework_observe_function_exit,
        rosette_application_framework_observe_control_transfer,
        rosette_application_framework_observe_value,
        rosette_application_framework_compare,
        rosette_application_framework_request,
        rosette_application_framework_take_request,
        rosette_application_framework_complete_request,
        rosette_application_framework_read_event,
        rosette_application_framework_snapshot,
};
