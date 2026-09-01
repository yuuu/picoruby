class SIM7672Test < Picotest::Test
  def setup
    @uart = UART.new(unit: :PICORB_UART_RP2040_UART0, baudrate: 115200)
    @sim = SIM7672.new(uart: @uart, log_size: 5)
  end

  def teardown
    clear_doubles
  end

  # Stub the UART so command() neither blocks on real IO nor talks to a device.
  def fake_uart(response)
    stub(@uart).puts { nil }
    stub(@uart).read { nil }
    stub(@sim).uart_read { response }
  end

  def test_initialize_defaults
    assert_equal "soracom.io", @sim.apn
    assert_equal "sora", @sim.username
    assert_equal "sora", @sim.password
    assert_equal "picoruby", @sim.user_agent
    assert_equal "IP", @sim.pdp_type
    assert_equal SIM7672::AUTH_CHAP, @sim.auth_type
    assert_equal [], @sim.log
    assert_equal 5, @sim.instance_variable_get(:@log_size)
    assert_equal "\r", @uart.instance_variable_get(:@line_ending)
  end

  def test_initialize_default_log_size
    uart = UART.new(unit: :PICORB_UART_RP2040_UART0, baudrate: 115200)
    sim = SIM7672.new(uart: uart)
    assert_equal 10, sim.instance_variable_get(:@log_size)
  end

  def test_on_without_status_pin
    assert_true @sim.on?
  end

  def test_command_success_and_logging
    fake_uart("OK\r\n")

    assert_true @sim.command("AT", "OK")
    assert_equal 1, @sim.log.size
    assert_equal "AT", @sim.log.first[:cmd]
    assert_true @sim.log.first[:res].include?("OK")
  end

  def test_command_error_response
    fake_uart("ERROR\r\n")
    assert_false @sim.command("AT+CPIN?", "+CPIN: READY", "ERROR")
  end

  def test_command_bang_raises_on_failure
    fake_uart("ERROR\r\n")
    assert_raise(RuntimeError) { @sim.command!("AT", "OK", "ERROR") }
  end

  def test_at_returns_raw_response
    fake_uart("\r\nSIM7672\r\nOK\r\n")
    assert_true @sim.at("ATI", 1).include?("SIM7672")
  end

  def test_log_ring_buffer_is_capped
    fake_uart("OK\r\n")
    8.times { @sim.command("AT", "OK") }
    assert_equal 5, @sim.log.size
  end

  def test_configure_pdp_context_sends_expected_at_commands
    fake_uart("OK\r\n")

    @sim.apn = "example.com"
    @sim.configure_pdp_context

    cmds = @sim.log.map { |entry| entry[:cmd] }
    assert_true cmds.include?('AT+CGDCONT=1,"IP","example.com"')
    assert_true cmds.any? { |c| c.start_with?("AT+CGAUTH=1,") }
  end

  def test_configure_pdp_context_skips_auth_when_no_username
    fake_uart("OK\r\n")

    @sim.username = ""
    @sim.configure_pdp_context

    cmds = @sim.log.map { |entry| entry[:cmd] }
    assert_false cmds.any? { |c| c.start_with?("AT+CGAUTH=") }
  end
end
