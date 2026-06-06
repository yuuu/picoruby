#include <stdint.h>
#include <mruby.h>
#include <mruby/presym.h>
#include <mruby/class.h>
#include <mruby/debug.h>
/* Full definition of struct mrb_irep (for irep->iseq in the fetch hook).
 * mruby/debug.h only forward-declares mrb_irep. */
#include <mruby/irep.h>
/* picorb_hal_write: console output without stdio.
 * Use an explicit relative path like machine.c does, because a bare
 * <hal.h> resolves to picoruby-mruby/include/hal.h (which does not
 * declare picorb_hal_write) instead of picoruby-machine's hal.h. */
#include "../../../picoruby-machine/include/hal.h"

/* Console output helpers (this code runs on microcontrollers where stdio.h
 * is not guaranteed to exist, so we use picorb_hal_write like machine.c). */
static int
debug_strlen(const char *s)
{
  int n = 0;
  if (!s) return 0;
  while (s[n]) n++;
  return n;
}

static void
debug_write(int fd, const char *s)
{
  picorb_hal_write(fd, s, debug_strlen(s));
}

static void
debug_write_int(int fd, int32_t n)
{
  char buf[12];
  int i = (int)sizeof(buf);
  int negative = (n < 0);
  uint32_t u = negative ? (uint32_t)(-(n + 1)) + 1u : (uint32_t)n;
  do {
    buf[--i] = (char)('0' + (u % 10));
    u /= 10;
  } while (u > 0 && i > 0);
  if (negative && i > 0) buf[--i] = '-';
  picorb_hal_write(fd, &buf[i], (int)sizeof(buf) - i);
}

#ifdef MRB_USE_DEBUG_HOOK

/* Milestone 1: just confirm the hook is invoked.
 * The hook fires on every VM instruction, so cap the output to avoid flooding. */
#define DEBUG_FETCH_PRINT_LIMIT 30

static int debug_fetch_count;

static void
debug_code_fetch_hook(mrb_state *mrb, const mrb_irep *irep,
                      const mrb_code *pc, mrb_value *regs)
{
  if (debug_fetch_count < DEBUG_FETCH_PRINT_LIMIT) {
    uint32_t off = (uint32_t)(pc - irep->iseq);
    const char *file = mrb_debug_get_filename(mrb, irep, off);
    int32_t line = mrb_debug_get_line(mrb, irep, off);
    debug_write(1, "[debug] code_fetch_hook: ");
    debug_write(1, file ? file : "(unknown)");
    debug_write(1, ":");
    debug_write_int(1, line);
    debug_write(1, "\n");
  }
  debug_fetch_count++;
}

#endif

static mrb_value
mrb_debugger_enable_hook(mrb_state *mrb, mrb_value self)
{
#ifdef MRB_USE_DEBUG_HOOK
  debug_fetch_count = 0;
  mrb->code_fetch_hook = debug_code_fetch_hook;
  return mrb_true_value();
#else
  debug_write(2, "[debug] MRB_USE_DEBUG_HOOK is not enabled in this build\n");
  return mrb_false_value();
#endif
}

static mrb_value
mrb_debugger_disable_hook(mrb_state *mrb, mrb_value self)
{
#ifdef MRB_USE_DEBUG_HOOK
  mrb->code_fetch_hook = NULL;
#endif
  return mrb_true_value();
}

void
mrb_picoruby_debug_gem_init(mrb_state *mrb)
{
  struct RClass *debugger =
    mrb_define_class_id(mrb, MRB_SYM(Debugger), mrb->object_class);
  mrb_define_method_id(mrb, debugger, MRB_SYM(enable_hook),
                       mrb_debugger_enable_hook, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, debugger, MRB_SYM(disable_hook),
                       mrb_debugger_disable_hook, MRB_ARGS_NONE());
}

void
mrb_picoruby_debug_gem_final(mrb_state *mrb)
{
}
