#include "../../include/rosette/xenia_host_gpu_callback.h"

typedef struct {
  uint32_t (*abi_version)(void);
  uint16_t (*schema_version)(void);
  int32_t (*query)(const rosette_xenia_host_gpu_callback_request_t*,
                   rosette_xenia_host_gpu_callback_response_t*);
  int32_t (*report)(const rosette_xenia_host_gpu_callback_request_t*,
                    const rosette_xenia_host_gpu_callback_response_t*,
                    uint32_t, uint8_t);
} rosette_xenia_host_gpu_callback_exports_t;

/* Keep the optional dlsym ABI visible in the final Mach-O image under
 * dead-strip. The anchor has no policy and no runtime side effects. */
__attribute__((used, retain)) static const
    rosette_xenia_host_gpu_callback_exports_t
        rosette_xenia_host_gpu_callback_exports_anchor = {
            rosette_xenia_host_gpu_callback_abi_version,
            rosette_xenia_host_gpu_callback_schema_version,
            rosette_xenia_host_gpu_callback_query,
            rosette_xenia_host_gpu_callback_report,
        };
