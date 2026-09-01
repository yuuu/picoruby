require 'uart'
require 'gpio'

# SIMCom SIM7672 (A7672 family, LTE Cat 1) cellular modem driver.
#
# The reference MicroPython implementation drives the module as a PPP dial-up
# device. PicoRuby has no PPP stack, so this driver instead follows the same
# approach as QuectelCellular: a modem control layer (power sequencing, SIM and
# network registration, PDP context configuration) plus AT-command IP clients
# (TCP / UDP / HTTPS) built on the SIMCom A76xx command set.
class SIM7672

  DEFAULT_BAUDRATE    = 115200
  DEFAULT_LOG_SIZE    = 10
  POWERON_TIMEOUT_MS  = 20000
  POWEROFF_TIMEOUT_MS = 10000
  POLL_INTERVAL_MS    = 100

  # AT+CGAUTH authentication types
  AUTH_NONE = 0
  AUTH_PAP  = 1
  AUTH_CHAP = 2

  # power_pin  : PWRKEY line (active high through the level shifter / transistor)
  # reset_pin  : RESET line
  # status_pin : STATUS / NETLIGHT output of the module (high when powered on)
  # Each pin argument accepts a GPIO instance or a pin number, or nil when the
  # line is not wired.
  def initialize(uart:, power_pin: nil, reset_pin: nil, status_pin: nil,
                 baudrate: DEFAULT_BAUDRATE, log_size: DEFAULT_LOG_SIZE, debug: false)
    @uart = uart
    # AT commands are terminated with CR. (UART#gets/#read are unaffected by
    # this; only UART#puts uses it, which is what command() sends with.)
    @uart.line_ending = "\r"
    @baudrate = baudrate
    @debug = debug
    @log = []
    @log_size = log_size
    @power_pin  = to_gpio(power_pin, GPIO::OUT)
    @reset_pin  = to_gpio(reset_pin, GPIO::OUT)
    @status_pin = to_gpio(status_pin, GPIO::IN)
    @apn = "soracom.io"
    @username = "sora"
    @password = "sora"
    @auth_type = AUTH_CHAP
    @pdp_type = "IP"
    @user_agent = "picoruby"
    debug_print "init: power_pin=#{!power_pin.nil?} reset_pin=#{!reset_pin.nil?} " \
                "status_pin=#{!status_pin.nil?} baudrate=#{baudrate}"
  end

  attr_accessor :apn, :username, :password, :user_agent, :pdp_type, :auth_type, :debug
  attr_reader :log

  # Trace a bring-up / data-plane step. Everything printed here is prefixed with
  # "[SIM7672]" so it is easy to grep apart from the raw "> " / "< " AT traffic
  # that command() prints. No-op unless `debug:` (or `sim.debug = true`) is set.
  def debug_print(msg)
    puts "[SIM7672] #{msg}" if @debug
  end

  def to_gpio(pin, dir)
    return nil if pin.nil?
    return pin if pin.is_a?(GPIO)
    GPIO.new(pin, dir)
  end

  #
  # Hardware / power control
  #

  # true when the STATUS line reports the module is powered on. When no STATUS
  # pin is wired we optimistically assume the module is on.
  def on?
    pin = @status_pin
    return true unless pin
    pin.read == 1
  end

  def power_key(hold_ms)
    pin = @power_pin
    unless pin
      puts "SIM7672: power_pin is not set"
      return
    end
    debug_print "power_key: PWRKEY high for #{hold_ms}ms"
    pin.write 1
    sleep_ms hold_ms
    pin.write 0
    debug_print "power_key: PWRKEY back low"
  end

  def poweron
    debug_print "poweron: begin (status_pin=#{!@status_pin.nil?}, on?=#{on?})"
    if @status_pin && on?
      debug_print "poweron: STATUS already high, nothing to do"
      return true
    end
    power_key 1000
    if @status_pin
      steps = POWERON_TIMEOUT_MS / POLL_INTERVAL_MS
      steps.times do |i|
        sleep_ms POLL_INTERVAL_MS
        if on?
          debug_print "poweron: STATUS went high after ~#{(i + 1) * POLL_INTERVAL_MS}ms"
          return true
        end
        debug_print "poweron: waiting STATUS #{((i + 1) * POLL_INTERVAL_MS) / 1000}s/#{POWERON_TIMEOUT_MS / 1000}s" if (i + 1) % 10 == 0
      end
      # STATUS never asserted: the line may be miswired / floating / inverted.
      # Fall back to probing the AT link so a bad STATUS pin is not fatal.
      debug_print "poweron: STATUS never went high in #{POWERON_TIMEOUT_MS}ms; " \
                  "falling back to AT probe (check STATUS wiring/polarity)"
      return sync
    end
    # No STATUS line to sense: give the module time to boot, then confirm
    # over AT.
    debug_print "poweron: no STATUS pin; waiting 5000ms for boot then AT probe"
    sleep_ms 5000
    result = sync
    debug_print "poweron: AT probe #{result ? 'ok' : 'FAILED'}"
    result
  end

  def poweroff
    debug_print "poweroff: begin (on?=#{on?})"
    if @status_pin && !on?
      debug_print "poweroff: STATUS already low, nothing to do"
      return true
    end
    power_key 3000
    return true unless @status_pin
    steps = POWEROFF_TIMEOUT_MS / POLL_INTERVAL_MS
    steps.times do |i|
      sleep_ms POLL_INTERVAL_MS
      unless on?
        debug_print "poweroff: STATUS went low after ~#{(i + 1) * POLL_INTERVAL_MS}ms"
        return true
      end
      debug_print "poweroff: waiting STATUS #{((i + 1) * POLL_INTERVAL_MS) / 1000}s/#{POWEROFF_TIMEOUT_MS / 1000}s" if (i + 1) % 10 == 0
    end
    debug_print "poweroff: STATUS still high after #{POWEROFF_TIMEOUT_MS}ms"
    false
  end

  # RESET must be asserted long enough for the module to latch it. The SIM7672
  # / MicroCat.1 spec is >=500ms; the MicroPython reference uses 1s.
  RESET_PULSE_MS = 1000

  def reset
    pin = @reset_pin
    raise "SIM7672: reset_pin is not set" unless pin
    debug_print "reset: pulsing RESET high for #{RESET_PULSE_MS}ms"
    pin.write 1
    sleep_ms RESET_PULSE_MS
    pin.write 0
    timeout_ms = POWERON_TIMEOUT_MS + POWEROFF_TIMEOUT_MS
    steps = timeout_ms / POLL_INTERVAL_MS
    steps.times do |i|
      sleep_ms POLL_INTERVAL_MS
      if on?
        debug_print "reset: STATUS high again after ~#{(i + 1) * POLL_INTERVAL_MS}ms"
        return true
      end
      debug_print "reset: waiting STATUS #{((i + 1) * POLL_INTERVAL_MS) / 1000}s/#{timeout_ms / 1000}s" if (i + 1) % 10 == 0
    end
    debug_print "reset: STATUS never came back in #{timeout_ms}ms"
    false
  end

  #
  # AT command plumbing (same design as QuectelCellular)
  #

  # Drain everything currently in the RX buffer. Reads raw bytes rather than
  # whole lines: AT responses are not always newline-terminated (e.g. the
  # "> " prompt from AT+CIPSEND / AT+HTTPDATA), and command() only does
  # substring matching, so line framing does not matter here.
  def uart_read
    sleep_ms 100
    buf = ""
    chunks = 0
    while (chunk = @uart.read)
      buf += chunk
      chunks += 1
      sleep_ms 5
    end
    debug_print "  rx #{buf.bytesize}B in #{chunks} chunk(s)" if @debug && !buf.empty?
    buf
  end

  # An empty cmd sends nothing and only waits for a response, which is useful
  # after streaming raw payload bytes (AT+CIPSEND, AT+HTTPDATA, ...).
  #
  # NOTE: this method must not `return` from inside the poll loop. Under the
  # mruby/c VM a `return` executed from within a loop of a method that also
  # carries an `ensure` clause runs the ensure but then yields the ensure
  # block's value instead of the returned one, so `command` would hand back
  # nil on a successful match. The loop therefore only sets `matched` / breaks,
  # and the single exit point at the bottom computes the result.
  def command(cmd, expected_response, error_response = nil, timeout = 5)
    matched = nil
    started = Time.now.to_f
    unless cmd.empty?
      puts "> #{cmd}" if @debug
      stale = @uart.read # discard any stale bytes before issuing the command
      debug_print "  discarded #{stale.bytesize}B of stale rx before send" if @debug && stale && !stale.empty?
      @uart.puts cmd
    end
    start = Time.new.to_i
    limit = start + timeout
    response = ""
    while Time.new.to_i < limit
      fragment = uart_read
      response << fragment unless fragment.empty?
      if expected_response && response.include?(expected_response)
        matched = expected_response
        break
      elsif error_response && response.include?(error_response)
        matched = error_response
        break
      end
      sleep_ms 50 # Prevent busy loop
    end
    result = !matched.nil? && matched == expected_response
    response << "\nTimeout!" if matched.nil?

    if @debug
      puts "< #{response}"
      elapsed_ms = started ? ((Time.now.to_f - started) * 1000).to_i : -1
      label = cmd.empty? ? "(wait only)" : cmd
      outcome = if result
                  "matched expected #{expected_response.inspect}"
                elsif !matched.nil?
                  "matched error #{error_response.inspect}"
                else
                  "TIMEOUT after #{timeout}s"
                end
      debug_print "  #{label} -> #{outcome} (#{elapsed_ms}ms)"
    end
    @log << { cmd: cmd, res: response }
    @log.shift if @log.size > @log_size

    result
  end

  def command!(cmd, expected_response, error_response = nil, timeout = 5)
    unless command(cmd, expected_response, error_response, timeout)
      response = (log = @log.last) ? log[:res] : ""
      raise "Command failed: #{cmd}\nResponse: #{response}"
    end
  end

  # Returns the accumulated response text of the most recent command.
  def last_response
    (log = @log.last) ? log[:res] : ""
  end

  # Send a raw AT command and return everything the modem replies within
  # `timeout` seconds. Intended for interactive debugging, e.g.
  #   sim.at("AT")            # => "" means nothing came back
  #   sim.at("ATI")           # module identification
  def at(cmd, timeout = 3)
    command(cmd, nil, nil, timeout)
    last_response
  end

  #
  # Modem bring-up
  #

  # Try to get the modem into a sane AT-command state: bare "AT" wakes the
  # autobaud detector, and "+++" drops it out of data mode if it is stuck
  # there. Returns false if the modem never answers "OK" (wrong wiring,
  # wrong baud rate, module still booting, or held off by flow control).
  def sync(retries = 8)
    debug_print "sync: probing AT link (up to #{retries} tries)"
    @uart.clear_rx_buffer
    retries.times do |i|
      if command('AT', 'OK', 'ERROR', 2)
        debug_print "sync: got OK on try #{i + 1}"
        return true
      end
      if i == 2
        debug_print "sync: no answer yet; sending +++ escape then ATH"
        @uart.write "+++"
        sleep_ms 1100
        command('ATH', 'OK', 'ERROR', 2)
      end
      sleep_ms 500
    end
    debug_print "sync: FAILED after #{retries} tries (wiring / baud / power / flow control?)"
    false
  end

  def setup_modem(flow_control: false)
    debug_print "setup_modem: begin (flow_control=#{flow_control})"
    raise "SIM7672 not responding to AT (check wiring / baud / power / flow control)" unless sync
    command!('ATE0', 'OK') # echo off
    if flow_control
      command!('AT+IFC=2,2', 'OK')
      @uart.setmode(flow_control: UART::FLOW_CONTROL_RTS_CTS)
    else
      command('AT+IFC=0,0', 'OK')
    end
    debug_print "setup_modem: done"
    true
  end

  def wait_sim_ready(retries = 20, delay_ms = 500)
    debug_print "wait_sim_ready: polling AT+CPIN? (up to #{retries} times)"
    retries.times do |i|
      if command('AT+CPIN?', '+CPIN: READY', 'ERROR', 5)
        debug_print "wait_sim_ready: SIM READY on poll #{i + 1}"
        return true
      end
      sleep_ms delay_ms
    end
    debug_print "wait_sim_ready: SIM never reported READY (no SIM / wrong PIN?)"
    false
  end

  def wait_registration(retries = 90, delay_ms = 1000)
    debug_print "wait_registration: AT+CGATT=1 then polling AT+CEREG? (up to #{retries}s)"
    command('AT+CGATT=1', 'OK', 'ERROR', 10)
    retries.times do |i|
      if command('AT+CEREG?', 'OK', 'ERROR', 5)
        res = last_response
        if res.include?(",1") || res.include?(",5")
          debug_print "wait_registration: registered on poll #{i + 1} (#{registration_stat(res)})"
          return true
        end
        debug_print "wait_registration: poll #{i + 1} not registered yet (#{registration_stat(res)})" if i % 10 == 0
      end
      sleep_ms delay_ms
    end
    debug_print "wait_registration: TIMEOUT, still not registered (antenna / APN / signal?)"
    false
  end

  # Best-effort extraction of the <stat> field from an "+CEREG: <n>,<stat>..."
  # reply, purely for debug output.
  def registration_stat(res)
    marker = res.split("+CEREG:")[1]
    return "no +CEREG" unless marker
    fields = marker.split("\n")[0].to_s.split(',')
    "stat=#{fields[1].to_s.strip}"
  end

  # Returns [rssi, ber] as reported by AT+CSQ, or nil when unavailable.
  def signal_quality
    return nil unless command('AT+CSQ', '+CSQ:', 'ERROR', 5)
    marker = last_response.split('+CSQ:')[1]
    return nil unless marker
    values = marker.split("\n")[0].to_s.split(',')
    return nil if values.size < 2
    result = [values[0].to_s.strip.to_i, values[1].to_s.strip.to_i]
    debug_print "signal_quality: rssi=#{result[0]} ber=#{result[1]}" \
                "#{result[0] == 99 ? ' (99 = unknown / no signal)' : ''}"
    result
  end

  def configure_pdp_context
    debug_print "configure_pdp_context: apn=#{@apn.inspect} pdp_type=#{@pdp_type} " \
                "auth_type=#{@auth_type} username=#{@username.inspect}"
    command!(%(AT+CGDCONT=1,"#{@pdp_type}","#{@apn}"), 'OK', 'ERROR', 10)
    unless @username.empty?
      command!(%(AT+CGAUTH=1,#{@auth_type},"#{@username}","#{@password}"), 'OK', 'ERROR', 10)
    end
    true
  end

  def check_sim_status
    debug_print "check_sim_status: begin"
    raise "SIM7672 not responding to AT (check wiring / baud / power / flow control)" unless sync
    command('ATE0', 'OK') # echo off
    raise "SIM not ready" unless wait_sim_ready
    command('AT+CIMI', 'OK')
    raise "Not registered to network" unless wait_registration
    debug_print "check_sim_status: ok"
    true
  end

  #
  # IP data plane (SIMCom A76xx TCP/IP AT commands)
  #

  def net_open
    debug_print "net_open: checking AT+NETOPEN?"
    if command('AT+NETOPEN?', '+NETOPEN: 1', nil, 5)
      debug_print "net_open: socket service already open"
      return true
    end
    opened = command('AT+NETOPEN', '+NETOPEN: 0', 'ERROR', 60)
    debug_print "net_open: AT+NETOPEN #{opened ? 'ok' : 'did NOT confirm +NETOPEN: 0'}"
    command!('AT+IPADDR', '+IPADDR:', 'ERROR', 10)
    debug_print "net_open: IP assigned"
    true
  end

  def net_close
    debug_print "net_close"
    command('AT+NETCLOSE', '+NETCLOSE: 0', 'ERROR', 10)
  end

  # Overridden by subclasses that need SSL or other extra configuration.
  def configure_and_activate_context
    debug_print "configure_and_activate_context: begin"
    setup_modem
    raise "SIM not ready" unless wait_sim_ready
    configure_pdp_context
    raise "Not registered to network" unless wait_registration
    net_open
    debug_print "configure_and_activate_context: done"
    true
  end

  # TCP client over AT+CIPOPEN / AT+CIPSEND / AT+CIPRXGET / AT+CIPCLOSE.
  class TCPClient < SIM7672
    def open(host, port, type: "TCP", link: 0)
      debug_print "TCPClient#open: link=#{link} #{type} #{host}:#{port}"
      command!(%(AT+CIPOPEN=#{link},"#{type}","#{host}",#{port}), "+CIPOPEN: #{link},0", 'ERROR', 150)
      debug_print "TCPClient#open: connected on link #{link}"
      link
    end

    def send(data, link: 0)
      debug_print "TCPClient#send: link=#{link} #{data.bytesize}B"
      command!("AT+CIPSEND=#{link},#{data.bytesize}", '>', 'ERROR', 10)
      @uart.write data
      command!('', '+CIPSEND:', 'ERROR', 30)
      debug_print "TCPClient#send: #{data.bytesize}B acked"
      data.bytesize
    end

    def recv(link: 0, length: 1500)
      debug_print "TCPClient#recv: link=#{link} up to #{length}B " \
                  "(needs AT+CIPRXGET=1 manual mode enabled beforehand)"
      unless command("AT+CIPRXGET=2,#{link},#{length}", 'OK', 'ERROR', 10)
        debug_print "TCPClient#recv: AT+CIPRXGET returned no OK"
        return ""
      end
      res = last_response
      marker = res.split("+CIPRXGET: 2,")[1]
      unless marker
        debug_print "TCPClient#recv: no +CIPRXGET: 2, marker in reply (0 bytes buffered?)"
        return ""
      end
      body = marker.split("\n", 2)[1]
      out = body ? body.to_s : ""
      debug_print "TCPClient#recv: got #{out.bytesize}B of payload"
      out
    end

    def close(link: 0)
      debug_print "TCPClient#close: link=#{link}"
      command("AT+CIPCLOSE=#{link}", "+CIPCLOSE: #{link},0", 'ERROR', 10)
    end
  end

  # UDP client: one-shot open / send / close per datagram.
  class UDPClient < SIM7672
    def send(host, port, data, link: 0)
      debug_print "UDPClient#send: link=#{link} #{host}:#{port} #{data.bytesize}B"
      command!(%(AT+CIPOPEN=#{link},"UDP","#{host}",#{port}), "+CIPOPEN: #{link},0", 'ERROR', 150)
      command!("AT+CIPSEND=#{link},#{data.bytesize}", '>', 'ERROR', 10)
      @uart.write data
      command!('', '+CIPSEND:', 'ERROR', 30)
      command("AT+CIPCLOSE=#{link}", "+CIPCLOSE: #{link},0", 'ERROR', 10)
      debug_print "UDPClient#send: datagram sent and link closed"
      data.bytesize
    end
  end

  # Soracom Beam UDP endpoint (beam.soracom.io:23080).
  class SoracomBeamUDP < UDPClient
    def send(data, link: 0)
      super("beam.soracom.io", 23080, data, link: link)
    end
  end

  # HTTP(S) client over the SIMCom AT+HTTP* command family.
  class HTTPSClient < SIM7672
    def initialize(uart:, cacert: nil, power_pin: nil, reset_pin: nil,
                   status_pin: nil, baudrate: DEFAULT_BAUDRATE, log_size: DEFAULT_LOG_SIZE,
                   debug: false)
      super(uart: uart, power_pin: power_pin, reset_pin: reset_pin,
            status_pin: status_pin, baudrate: baudrate, log_size: log_size, debug: debug)
      @cacert = cacert # file name already stored on the module (see #upload_file)
    end

    # SSL context index bound to the HTTP service via AT+HTTPPARA="SSLCFG",<n>.
    SSL_CTX_ID = 0

    # PDP context id the HTTP service binds to (AT+HTTPPARA="CID",<n>).
    HTTP_CID = 1

    def configure_and_activate_context
      debug_print "HTTPSClient#configure_and_activate_context: begin (cacert=#{@cacert.inspect})"
      setup_modem
      raise "SIM not ready" unless wait_sim_ready
      configure_pdp_context
      raise "Not registered to network" unless wait_registration
      # Do NOT open the socket TCP/IP service (AT+NETOPEN) here. The AT+HTTP*
      # stack manages its own bearer through the PDP context, and on A76xx
      # firmware a concurrently-open NETOPEN makes HTTPACTION fail fast with
      # +HTTPACTION: <m>,715. Close it if a previous run left it open, then
      # activate the PDP context the HTTP service will use.
      if command('AT+NETOPEN?', '+NETOPEN: 1', nil, 5)
        debug_print "HTTPSClient#configure_and_activate_context: closing socket service (AT+NETCLOSE)"
        command('AT+NETCLOSE', '+NETCLOSE: 0', 'ERROR', 20)
      end
      debug_print "HTTPSClient#configure_and_activate_context: activating PDP context #{HTTP_CID}"
      command("AT+CGACT=1,#{HTTP_CID}", 'OK', 'ERROR', 30)
      # SSL context 0 must be configured before AT+HTTPPARA="SSLCFG",0. Do this
      # for every HTTPS run, not only when a CA cert is supplied.
      debug_print "HTTPSClient#configure_and_activate_context: configuring TLS ctx #{SSL_CTX_ID}"
      command!(%(AT+CSSLCFG="sslversion",#{SSL_CTX_ID},4), 'OK', 'ERROR', 10)
      if @cacert
        command!(%(AT+CSSLCFG="authmode",#{SSL_CTX_ID},1), 'OK', 'ERROR', 10)
        command!(%(AT+CSSLCFG="cacert",#{SSL_CTX_ID},"#{@cacert}"), 'OK', 'ERROR', 10)
      else
        # No CA bundle uploaded: do not verify the server certificate.
        command!(%(AT+CSSLCFG="authmode",#{SSL_CTX_ID},0), 'OK', 'ERROR', 10)
      end
      # CDN-fronted hosts (example.com included) reject a TLS handshake with no
      # SNI, which the module surfaces as +HTTPACTION: <m>,715. SNI defaults to
      # off on A76xx. ignorelocaltime keeps a wrong RTC from breaking cert time
      # checks. Both params are absent on some firmware; ignore ERROR.
      command(%(AT+CSSLCFG="enableSNI",#{SSL_CTX_ID},1), 'OK', 'ERROR', 10)
      command(%(AT+CSSLCFG="ignorelocaltime",#{SSL_CTX_ID},1), 'OK', 'ERROR', 10)
      debug_print "HTTPSClient#configure_and_activate_context: done"
      true
    end

    # Write a file (e.g. a CA certificate) to the module's flash file system
    # using AT+CFSWFILE so it can be referenced by #configure_and_activate_context.
    def upload_file(name, data)
      debug_print "upload_file: #{name.inspect} #{data.bytesize}B"
      command!('AT+CFSINIT', 'OK', 'ERROR', 10)
      command!(%(AT+CFSWFILE=3,"#{name}",0,#{data.bytesize},10000), 'DOWNLOAD', 'ERROR', 10)
      @uart.write data
      command!('', 'OK', 'ERROR', 20)
      command('AT+CFSTERM', 'OK', 'ERROR', 10)
      debug_print "upload_file: #{name.inspect} stored"
      name
    end

    def get(url, headers = {})
      request(0, url, nil, headers)
    end

    def post(url, body, headers = {})
      request(1, url, body, headers)
    end

    def request(method_code, url, body, headers)
      debug_print "HTTPSClient#request: method=#{method_code} url=#{url.inspect} " \
                  "body=#{body ? "#{body.bytesize}B" : 'none'} headers=#{headers.size}"
      # `result` is assigned inside the begin and read as the method's final
      # statement, outside the ensure. See the note on #command: mruby/c does
      # not reliably carry an implicit body value out through `ensure`.
      result = nil #: SIM7672::http_response_t?
      begin
        command!('AT+HTTPINIT', 'OK', 'ERROR', 10)
        # Bind to the activated PDP context. Not every A76xx firmware supports
        # this param; ignore ERROR (it then uses the default context).
        command(%(AT+HTTPPARA="CID",#{HTTP_CID}), 'OK', 'ERROR', 10)
        command!(%(AT+HTTPPARA="URL","#{url}"), 'OK', 'ERROR', 10)
        if url.start_with?("https")
          debug_print "HTTPSClient#request: https URL -> AT+HTTPPARA=\"SSLCFG\",#{SSL_CTX_ID}"
          command!(%(AT+HTTPPARA="SSLCFG",#{SSL_CTX_ID}), 'OK', 'ERROR', 10)
        end
        unless headers.empty?
          lines = [] #: Array[String]
          headers.each { |k, v| lines << "#{k}: #{v}" }
          command!(%(AT+HTTPPARA="USERDATA","#{lines.join("\\r\\n")}"), 'OK', 'ERROR', 10)
        end
        if body
          debug_print "HTTPSClient#request: uploading #{body.bytesize}B request body"
          command!("AT+HTTPDATA=#{body.bytesize},10000", 'DOWNLOAD', 'ERROR', 10)
          @uart.write body
          command!('', 'OK', 'ERROR', 20)
        end
        debug_print "HTTPSClient#request: AT+HTTPACTION=#{method_code} (waiting for +HTTPACTION URC)"
        command!("AT+HTTPACTION=#{method_code}", "+HTTPACTION: #{method_code},", 'ERROR', 60)
        action = parse_http_action(method_code)
        status = action[0] || 0
        length = action[1] || 0
        debug_print "HTTPSClient#request: HTTP status=#{status} content-length=#{length}"
        if status < 100 || 599 < status
          # Not an HTTP status: the SIMCom stack failed before/at the request
          # (7xx = DNS / TCP / TLS / bearer error). Reading HEAD/BODY would just
          # return ERROR, so stop here and surface the modem code.
          debug_print "HTTPSClient#request: modem-side failure, code #{status} (not an HTTP status)"
          result = { status: status, headers: "", body: "" } #: SIM7672::http_response_t
        else
          command('AT+HTTPHEAD', 'OK', 'ERROR', 10)
          response_headers = last_response
          command("AT+HTTPREAD=0,#{length}", '+HTTPREAD: 0', 'ERROR', 30)
          response_body = extract_http_read(last_response)
          debug_print "HTTPSClient#request: headers=#{response_headers.bytesize}B body=#{response_body.bytesize}B"
          result = { status: status, headers: response_headers, body: response_body } #: SIM7672::http_response_t
        end
      ensure
        debug_print "HTTPSClient#request: AT+HTTPTERM (cleanup)"
        command('AT+HTTPTERM', 'OK', 'ERROR', 10)
      end
      result
    end

    def parse_http_action(method_code)
      marker = last_response.split("+HTTPACTION: #{method_code},")[1]
      return [0, 0] unless marker
      fields = marker.split("\n")[0].to_s.split(',')
      status = fields[0].to_s.strip.to_i
      length = fields[1].to_s.strip.to_i
      [status, length]
    end

    def extract_http_read(res)
      marker = res.split("+HTTPREAD: ")[1]
      return "" unless marker
      body = marker.split("\n", 2)[1]
      return "" unless body
      # Drop the trailing "+HTTPREAD: 0" terminator line if present.
      body.split("+HTTPREAD: 0")[0].to_s
    end
  end
end
