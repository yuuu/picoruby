# picoruby-sim7672

SIMCom **SIM7672** (A7672 family, LTE Cat 1) cellular modem driver for PicoRuby.

## Overview

This gem provides a Ruby interface for controlling a SIM7672 module over UART with
AT commands, plus optional GPIO control of the `PWRKEY` / `RESET` / `STATUS` lines.

The [MicroPython reference implementation][mpy] drives the module purely as a PPP
dial-up device. PicoRuby has no PPP stack, so this driver takes the same approach as
`picoruby-quectel_cellular`: a modem control layer (power sequencing, SIM and network
registration, PDP context configuration) plus AT-command IP clients (TCP / UDP /
HTTPS) built on the SIMCom A76xx command set. PPP data mode is out of scope.

[mpy]: https://github.com/takao2704/micropython/blob/31ec4028fc01013651eb24742a781599ecbf4151/ports/rp2/boards/MTX_MICROCAT1/modules/SIM7672.py

## Supported module

- SIM7672 / A7672 (LTE Cat 1, SIMCom A76xx AT command set)

## Enabling the gem

It is not part of any gembox. Add it to your build config:

```ruby
conf.gem core: 'picoruby-sim7672'
```

## Wiring

| Signal      | Notes                                                     |
|-------------|---------------------------------------------------------- |
| UART TXD/RXD| Cross-connected to the module's RXD/TXD, 115200 8N1       |
| `PWRKEY`    | `power_pin:` — pulsed high to toggle power                |
| `RESET`     | `reset_pin:` — pulsed high to hard reset                  |
| `STATUS`    | `status_pin:` — read to detect power state (high == on)   |

Any pin argument accepts a `GPIO` instance, a pin number, or `nil` when not wired.

### mechatrax MicroCat.1

MicroCat.1 pairs an **RP2350B** with an on-board SIM7672JP. The modem is on
fixed pins and needs an RP2350B firmware (the stock `pico2` build is RP2350A and
cannot reach GPIO ≥ 30):

```
rake r2p2:femtoruby:microcat1:prod
# -> build/r2p2/femtoruby/microcat1/prod/R2P2-FEMTORUBY-*-MICROCAT1-*.uf2
```

| Signal      | GPIO | Notes                                             |
|-------------|------|--------------------------------------------------|
| UART1 TX    | 36   | → modem RXD                                       |
| UART1 RX    | 37   | ← modem TXD                                       |
| UART1 CTS   | 38   | pass `cts_pin: 38` for HW flow control            |
| UART1 RTS   | 39   | pass `rts_pin: 39` for HW flow control            |
| `PWRKEY`    | 30   | `power_pin: 30`, active high                      |
| `RESET`     | 31   | `reset_pin: 31`, active high (≥ 500 ms)           |
| `STATUS`    | 32   | `status_pin: 32`, active high                     |

```ruby
uart = UART.new(unit: :RP2040_UART1, txd_pin: 36, rxd_pin: 37, baudrate: 115200)
sim  = SIM7672::HTTPSClient.new(uart: uart, power_pin: 30, reset_pin: 31,
                               status_pin: 32, debug: true)
```

See [example/microcat1_http_get.rb](example/microcat1_http_get.rb).

## Usage

### Power control

```ruby
require 'sim7672'

uart = UART.new(unit: :RP2040_UART1, txd_pin: 8, rxd_pin: 9, baudrate: 115200)
sim  = SIM7672.new(uart: uart, power_pin: 14, reset_pin: 15, status_pin: 16)

sim.poweron   # => true once STATUS goes high
sim.on?       # => true / false
sim.reset
sim.poweroff
```

### TCP

```ruby
client = SIM7672::TCPClient.new(uart: uart)
client.check_sim_status
client.configure_and_activate_context
client.open("example.com", 80)
client.send("GET / HTTP/1.0\r\nHost: example.com\r\n\r\n")
puts client.recv
client.close
```

### UDP (incl. Soracom Beam)

```ruby
udp = SIM7672::UDPClient.new(uart: uart)
udp.configure_and_activate_context
udp.send("192.0.2.1", 12345, "hello")

beam = SIM7672::SoracomBeamUDP.new(uart: uart)
beam.configure_and_activate_context
beam.send('{"temp":23.4}')
```

### HTTPS

```ruby
client = SIM7672::HTTPSClient.new(uart: uart, cacert: nil)
client.check_sim_status
client.configure_and_activate_context

res = client.get("https://example.com/")
puts res[:status]
puts res[:body]

res = client.post("https://example.com/api", '{"k":"v"}', {"Content-Type" => "application/json"})
```

To verify a server certificate, upload a CA bundle to the module's flash file system
first and pass its name as `cacert:`:

```ruby
client.upload_file("cacert.pem", File.read("cacert.pem"))
```

See [example/http_get.rb](example/http_get.rb) for a full flow.

## Troubleshooting

`Command failed: ... Timeout!` with an **empty** response means the modem sent
nothing back. Work through:

```ruby
sim = SIM7672.new(uart: uart, power_pin: 14, status_pin: 16, debug: true)
sim.poweron          # needs power_pin wired; with status_pin it waits for STATUS
sim.on?              # STATUS state (true if no status_pin is wired)
sim.at("AT")         # raw reply within 3 s; "" == nothing received
sim.at("ATI")
```

- **`debug: true`** traces the bring-up live. Three kinds of line are printed:
  - `> AT+...` / `< ...` — the raw command sent and the raw reply received.
  - `  ...` (two-space indent) — per-command detail: bytes read from the UART and
    in how many chunks, stale bytes discarded before a send, and the match result
    (`matched expected "OK"` / `matched error "ERROR"` / `TIMEOUT after 5s`) with
    the elapsed time in ms.
  - `[SIM7672] ...` — the high-level step: which phase is running
    (`poweron`, `sync`, `wait_sim_ready`, `wait_registration`, `net_open`,
    `configure_and_activate_context`, `HTTPSClient#request`, ...), the decision it
    took, and whether it succeeded. Grep for `[SIM7672]` to see the flow without
    the raw AT noise.
- Empty reply from `at("AT")` ⇒ the module is off / still booting (wait 10–15 s
  after power-up), TXD/RXD are swapped, the baud rate is wrong (default 115200),
  or hardware flow control is holding the module's TX. If `RTS`/`CTS` are wired,
  either construct with those pins and call
  `setup_modem(flow_control: true)`, or tie the module's `CTS` low.
- `poweron` only pulses `PWRKEY` when `power_pin:` is given. Without `status_pin:`
  it cannot sense the module and just waits a fixed boot delay.

## Configuration

Defaults target Soracom; override via accessors before
`configure_and_activate_context`:

```ruby
sim.apn       = "soracom.io"
sim.username  = "sora"
sim.password  = "sora"
sim.auth_type = SIM7672::AUTH_CHAP # AUTH_NONE / AUTH_PAP / AUTH_CHAP
sim.pdp_type  = "IP"
```

Every AT exchange is recorded in `sim.log` (a ring buffer, `log_size:` entries) for
debugging; `sim.last_response` returns the reply text of the most recent command.
Pass `debug: true` to `new` (or set `sim.debug = true`) to trace traffic live.

## API Reference

See [sig/sim7672.rbs](sig/sim7672.rbs) for complete API signatures.
