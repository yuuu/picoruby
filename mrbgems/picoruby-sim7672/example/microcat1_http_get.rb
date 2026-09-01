require 'sim7672'

# mechatrax MicroCat.1 (RP2350B + SIM7672JP).
#
# Fixed board wiring (see https://github.com/mechatrax/microcat1/wiki):
#   GPIO36 UART1 TX -> modem RXD      GPIO30 -> PWRKEY  (power control, active high)
#   GPIO37 UART1 RX <- modem TXD      GPIO31 -> RESET   (active high, >=500ms)
#   GPIO38 UART1 CTS                  GPIO32 <- STATUS  (power status, active high)
#   GPIO39 UART1 RTS
#
# Requires an RP2350B firmware build:  rake r2p2:femtoruby:microcat1:prod
uart = UART.new(unit: :RP2040_UART1, txd_pin: 36, rxd_pin: 37, baudrate: 115200)

client = SIM7672::HTTPSClient.new(
  uart:       uart,
  power_pin:  30,
  reset_pin:  31,
  status_pin: 32,
  debug:      true,
  cacert:     nil
)

# APN defaults target Soracom. Override here for other carriers:
# client.apn = "..."; client.username = "..."; client.password = "..."
# client.auth_type = SIM7672::AUTH_NONE

unless client.poweron
  puts "poweron() could not confirm the module."
  puts "last modem reply: #{client.last_response.inspect}"
  raise "SIM7672 did not power on"
end

client.check_sim_status
puts "signal quality: #{client.signal_quality.inspect}"
client.configure_and_activate_context

# DNS sanity check (helps tell a name-resolution failure apart from a TLS one).
puts "DNS example.com: #{client.at('AT+CDNSGIP="example.com"', 10).inspect}"

# Plain HTTP first to isolate TLS from bearer/DNS, then HTTPS.
http = client.get("http://example.com/")
puts "HTTP  status: #{http[:status]}"

res = client.get("https://example.com/")
puts "HTTPS status: #{res[:status]}"
puts "headers:\n#{res[:headers]}"
puts "body:\n#{res[:body]}"
