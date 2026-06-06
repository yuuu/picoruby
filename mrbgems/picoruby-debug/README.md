# picoruby-debug

A debugger for PicoRuby. **mruby only** — on mruby/c it prints an "unsupported"
message and does nothing.

This gem is the foundation for an interactive debugger. As a first milestone it
installs mruby's `code_fetch_hook` and confirms that the hook is invoked while a
script runs inside a `Sandbox` (a fresh mruby execution context).

## Usage

```ruby
require 'debug'

Debugger.new(ARGV[0]).start
```

`Debugger#start` reads the script at the given path, compiles it in a `Sandbox`,
installs `code_fetch_hook`, runs the script, and removes the hook afterwards.

While running you should see lines such as:

```
[debug] code_fetch_hook: /test.rb:1
```

which confirm the hook fires for each fetched VM instruction (output is capped to
avoid flooding the console).

## Requirements

`code_fetch_hook` is only compiled into the VM when `MRB_USE_DEBUG_HOOK` is
defined (mapped from `MRB_ENABLE_DEBUG_HOOK` in `mrbconf.h`). This define is
**not** added by `conf.enable_debug` (which only defines `MRB_DEBUG`).

Because it is build-wide (it changes `sizeof(mrb_state)` and the hook is invoked
from the VM core, `vm.c`), this gem sets the define itself via `build.cc.defines`
in its `mrbgem.rake` — the same approach `picoruby-mruby` uses for `MRB_NO_BOXING`
etc. So you do **not** need to add the define to the build config.

## Build config setup

The only change needed in the build config is to compile this gem in. Edit the
build config you build with — in R2P2-ESP32 these are
`components/picoruby-esp32/build_config/xtensa-esp-picoruby.rb` (Xtensa cores:
ESP32 / ESP32-S3) and `components/picoruby-esp32/build_config/riscv-esp-picoruby.rb`
(RISC-V cores: ESP32-C3 / C6 etc.).

Add a single line inside the existing `if ENV['PICORB_DEBUG']` block:

```ruby
  if ENV['PICORB_DEBUG']
    conf.cc.defines << 'ESTALLOC_DEBUG'
    conf.enable_debug
    conf.compilers.each { |c| c.flags << '-Og' }
    conf.gem core: 'picoruby-debug'   # <- add this line
  end
```

Placing it inside the `PICORB_DEBUG` block keeps normal builds free of the gem
and the per-instruction hook (no binary-size / speed cost), since the
`MRB_ENABLE_DEBUG_HOOK` define is only added when this gem is part of the build.

Then build with the flag enabled:

```sh
PICORB_DEBUG=1 idf.py build
```

## Dependencies

- `picoruby-sandbox`
- `picoruby-machine` (for `picorb_hal_write`, the stdio-free console output)
