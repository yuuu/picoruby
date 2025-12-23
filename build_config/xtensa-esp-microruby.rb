MRuby::CrossBuild.new('esp32-microruby') do |conf|
  conf.toolchain('gcc')

  conf.cc.command = "xtensa-esp32-elf-gcc"
  conf.linker.command = "xtensa-esp32-elf-ld"
  conf.archiver.command = "xtensa-esp32-elf-ar"

  conf.cc.host_command = 'gcc'
  conf.cc.flags << '-Wall'
  conf.cc.flags << '-Wno-format'
  conf.cc.flags << '-Wno-unused-function'
  conf.cc.flags << '-Wno-maybe-uninitialized'
  conf.cc.flags << "-mlongcalls"

  conf.cc.defines << 'MRB_TICK_UNIT=10'
  conf.cc.defines << 'MRB_TIMESLICE_TICK_COUNT=1'
  conf.cc.defines << 'MRBC_CONVERT_CRLF=1'
  conf.cc.defines << 'USE_FAT_FLASH_DISK'
  conf.cc.defines << 'NDEBUG'
  conf.cc.defines << "ESP32_PLATFORM"

  if ENV['PICORUBY_DEBUG']
    conf.cc.defines << "ESTALLOC_DEBUG"
    conf.enable_debug
  end

  conf.microruby
  conf.gembox "minimum"
  conf.gembox "core"
end
