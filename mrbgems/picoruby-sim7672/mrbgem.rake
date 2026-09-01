MRuby::Gem::Specification.new('picoruby-sim7672') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Yuhei Okazaki'
  spec.summary = 'SIMCom SIM7672 (A7672) LTE Cat 1 cellular modem driver for PicoRuby'

  spec.add_dependency 'picoruby-uart'
  spec.add_dependency 'picoruby-gpio'
end
