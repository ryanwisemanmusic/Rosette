#include "../../include/rosette/xenia_launch_assist.h"

typedef struct {
  uint32_t (*abi_version)(void);
  uint16_t (*schema_version)(void);
  int32_t (*query)(const rosette_xenia_launch_assist_request_t*,
                   rosette_xenia_launch_assist_response_t*);
  int32_t (*report)(const rosette_xenia_launch_assist_request_t*,
                    const rosette_xenia_launch_assist_response_t*, uint32_t,
                    uint8_t);
} rosette_xenia_launch_assist_exports_t;

/* Keep the optional dlsym ABI visible in the final Mach-O image under
 * dead-strip. The anchor contains no policy and has no runtime side effects.
 */
__attribute__((used, retain)) static const rosette_xenia_launch_assist_exports_t
    rosette_xenia_launch_assist_exports_anchor = {
        rosette_xenia_launch_assist_abi_version,
        rosette_xenia_launch_assist_schema_version,
        rosette_xenia_launch_assist_query,
        rosette_xenia_launch_assist_report,
};
