#include <mrubyc.h>

static void
c_pcnt__init(mrbc_vm *vm, mrbc_value *v, int argc)
{
  int ret = PCNT_init(
    (uint32_t)GET_INT_ARG(1),
    (uint32_t)GET_INT_ARG(2),
    (uint32_t)GET_INT_ARG(3),
    GET_TT_ARG(4) == MRBC_TT_TRUE
  );
  SET_INT_RETURN(ret);
}

static void
c_pcnt__count(mrbc_vm *vm, mrbc_value *v, int argc)
{
  int32_t count;
  if (PCNT_get_count(GET_INT_ARG(1), &count) != 0) {
    mrbc_raise(vm, MRBC_CLASS(RuntimeError), "PCNT: failed to get count");
    return;
  }
  SET_INT_RETURN(count);
}

static void
c_pcnt__clear(mrbc_vm *vm, mrbc_value *v, int argc)
{
  SET_INT_RETURN(PCNT_clear(GET_INT_ARG(1)));
}

void
mrbc_pcnt_init(mrbc_vm *vm)
{
  mrbc_class *mrbc_class_PCNT = mrbc_define_class(vm, "PCNT", mrbc_class_object);
  mrbc_define_method(vm, mrbc_class_PCNT, "_init", c_pcnt__init);
  mrbc_define_method(vm, mrbc_class_PCNT, "_count", c_pcnt__count);
  mrbc_define_method(vm, mrbc_class_PCNT, "_clear", c_pcnt__clear);
}
