require 'sim7672'

# Wiring (example, adjust to your board):
#   UART1 TXD -> SIM7672 RXD, UART1 RXD -> SIM7672 TXD
#   GPIO 14   -> PWRKEY (through level shifter / transistor)
#   GPIO 15   -> RESET
#   GPIO 16   <- STATUS / NETLIGHT
uart = UART.new(unit: :RP2040_UART1, txd_pin: 8, rxd_pin: 9, baudrate: 115200)

client = SIM7672::HTTPSClient.new(
  uart:       uart,
  power_pin:  14,
  reset_pin:  15,
  status_pin: 16,
  debug:      true, # trace every AT exchange while bringing the link up
  cacert:     nil # or "cacert.pem" after client.upload_file("cacert.pem", File.read("cacert.pem"))
)

unless client.poweron
  # poweron() pulses PWRKEY, waits for STATUS, then probes the AT link.
  # A failure here almost always means wiring / baud / power, not software.
  puts "poweron() could not confirm the module; check: TXD/RXD, baud 115200,"
  puts "PWRKEY wiring/polarity, STATUS pin, hardware flow control."
  puts "last modem reply: #{client.last_response.inspect}"
  raise "SIM7672 did not power on"
end

client.check_sim_status
puts "signal quality: #{client.signal_quality.inspect}"
client.configure_and_activate_context

res = client.get("https://example.com/")
puts "status: #{res[:status]}"
puts "headers:\n#{res[:headers]}"
puts "body:\n#{res[:body]}"
