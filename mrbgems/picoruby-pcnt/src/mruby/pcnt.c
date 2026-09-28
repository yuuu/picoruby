#include <mruby.h>
#include <mruby/presym.h>

static mrb_value
mrb_pcnt__init(mrb_state *mrb, mrb_value self)
{
  mrb_int pin_a, pin_b, glitch_ns;
  mrb_bool pull_up;
  mrb_get_args(mrb, "iiib", &pin_a, &pin_b, &glitch_ns, &pull_up);

  int ret = PCNT_init((uint32_t)pin_a, (uint32_t)pin_b, (uint32_t)glitch_ns, pull_up);
  return mrb_fixnum_value(ret);
}

static mrb_value
mrb_pcnt__count(mrb_state *mrb, mrb_value self)
{
  mrb_int unit_id;
  mrb_get_args(mrb, "i", &unit_id);

  int32_t count;
  if (PCNT_get_count((int)unit_id, &count) != 0) {
    mrb_raise(mrb, E_RUNTIME_ERROR, "PCNT: failed to get count");
  }
  return mrb_fixnum_value(count);
}

static mrb_value
mrb_pcnt__clear(mrb_state *mrb, mrb_value self)
{
  mrb_int unit_id;
  mrb_get_args(mrb, "i", &unit_id);
  return mrb_fixnum_value(PCNT_clear((int)unit_id));
}

void
mrb_picoruby_pcnt_gem_init(mrb_state* mrb)
{
  struct RClass *class_PCNT = mrb_define_class_id(mrb, MRB_SYM(PCNT), mrb->object_class);

  mrb_define_method_id(mrb, class_PCNT, MRB_SYM(_init), mrb_pcnt__init, MRB_ARGS_REQ(4));
  mrb_define_method_id(mrb, class_PCNT, MRB_SYM(_count), mrb_pcnt__count, MRB_ARGS_REQ(1));
  mrb_define_method_id(mrb, class_PCNT, MRB_SYM(_clear), mrb_pcnt__clear, MRB_ARGS_REQ(1));
}

void
mrb_picoruby_pcnt_gem_final(mrb_state* mrb)
{
}
