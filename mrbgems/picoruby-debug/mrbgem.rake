MRuby::Gem::Specification.new('picoruby-debug') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Yuhei Okazaki'
  spec.summary = 'Debugger for PicoRuby (mruby only)'

  spec.add_dependency 'picoruby-sandbox'
  spec.add_dependency 'picoruby-machine'

  if build.vm_mruby?
    # Enable mrb_state.code_fetch_hook. This must be a build-wide define because
    # it changes sizeof(mrb_state) and the hook is invoked from the VM core
    # (vm.c). Use build.defines (not build.cc.defines): build.defines is applied
    # to every gem's compilation via Command::Compiler#all_flags, whereas
    # build.cc.defines is only captured by gem compilers cloned *after* this
    # block runs -- this gem's own debug.c is cloned before it and would miss
    # the define. (Same approach as the profile defines in picoruby-mruby.)
    # NOTE: ESP-IDF-compiled units must agree on sizeof(mrb_state), so this is
    # mirrored as -DMRB_USE_DEBUG_HOOK in components/picoruby-esp32/CMakeLists.txt.
    unless build.defines.include?('MRB_USE_DEBUG_HOOK')
      build.defines << 'MRB_USE_DEBUG_HOOK'
    end
    # Required for mrb_state.code_fetch_hook and mruby/debug.h
    spec.cc.include_paths << "#{MRUBY_ROOT}/mrbgems/picoruby-mruby/lib/mruby/include"
    spec.cc.include_paths << "#{dir}/../picoruby-machine/include"
  end
end
