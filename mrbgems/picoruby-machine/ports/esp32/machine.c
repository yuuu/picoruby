#include "../../include/hal.h"

#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

typedef int bool;
typedef unsigned int uint;

void
hal_init(void)
{
}

void
hal_enable_irq()
{
}

void
hal_disable_irq()
{
}

void
hal_idle_cpu()
{
}

int
hal_write(int fd, const void *buf, int nbytes)
{
  return 0;
}

int hal_flush(int fd) {
  return 0;
}

int
hal_read_available(void)
{
  return 0;
}

int
hal_getchar(void)
{
  return 0;
}

void
hal_abort(const char *s)
{
}


/*-------------------------------------
 *
 * USB
 *
 *------------------------------------*/

void
Machine_tud_task(void)
{
}

bool
Machine_tud_mounted_q(void)
{
  return 0;
}


/*-------------------------------------
 *
 * RTC
 *
 *------------------------------------*/

/*
 * deep_sleep doesn't work yet
 */
void
Machine_deep_sleep(uint8_t gpio_pin, bool edge, bool high)
{
}

void
Machine_sleep(uint32_t seconds)
{
}

void
Machine_delay_ms(uint32_t ms)
{
}

void
Machine_busy_wait_ms(uint32_t ms)
{
}

int
Machine_get_unique_id(char *id_str)
{
  return 0;
}
