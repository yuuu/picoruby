#ifndef PCNT_DEFINED_H_
#define PCNT_DEFINED_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Returns a unit id (>= 0) or a negative value on failure. */
int PCNT_init(uint32_t pin_a, uint32_t pin_b, uint32_t glitch_ns, bool pull_up);
int PCNT_get_count(int unit_id, int32_t *count);
int PCNT_clear(int unit_id);

#ifdef __cplusplus
}
#endif

#endif /* PCNT_DEFINED_H_ */
