#include "pcnt.h"

#if defined(PICORB_VM_MRUBY)

#include "mruby/pcnt.c"

#elif defined(PICORB_VM_MRUBYC)

#include "mrubyc/pcnt.c"

#endif
