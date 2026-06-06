#include <mrubyc.h>

/* The Debugger is implemented in mrblib/debug.rb and supports mruby only.
 * On mruby/c it just prints an "unsupported" message (see mrblib/debug.rb),
 * so this init does nothing. */
void
mrbc_debug_init(mrbc_vm *vm)
{
}
