require 'sandbox'

class Debugger
  def initialize(path = nil)
    @path = path
  end

  def start
    if RUBY_ENGINE == 'mruby/c'
      puts "Debugger is not supported on mruby/c"
      return false
    end
    unless @path
      puts "Debugger: no script specified"
      return false
    end

    sandbox = Sandbox.new('debugger')
    f = File.open(@path, "r")
    begin
      code = f.read
    ensure
      f.close
    end
    unless code && sandbox.compile(code)
      puts "Debugger: compile failed: #{@path}"
      return false
    end

    # Install the hook only around the target script execution.
    enable_hook
    sandbox.execute
    sandbox.wait
    disable_hook

    if err = sandbox.error
      puts "#{err.class}: #{err.message}"
    end
    sandbox.terminate
    true
  end
end
