MRuby::CrossBuild.new('esp32') do |conf|
  toolchain :gcc

  conf.cc do |cc|
    cc.command = "xtensa-esp-elf-gcc"
    cc.flags << "-Wall"

    cc.defines << "MRBC_USE_HAL_ESP32"
    cc.defines << "PICORUBY_METAPROG_DISABLE_RBCONFIG_RUBY"
    cc.defines << "MRBC_TIMESLICE_TICK_COUNT=1"
    cc.defines << "MRBC_TICK_UNIT=10"
  end

  conf.linker.command = "xtensa-esp-elf-ld"
  conf.archiver.command = "xtensa-esp-elf-ar"

  conf.gem core: 'picoruby-machine'
  conf.gem core: "picoruby-shell"

  conf.picoruby
end
