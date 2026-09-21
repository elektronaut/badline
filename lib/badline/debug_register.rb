# frozen_string_literal: true

module Badline
  # The VICE debug cartridge register, mapped at $D7FF on the C64. It is a
  # VICE facility rather than real hardware, enabled there with -debugcart:
  # writing a byte ends the run with that value as the exit code. The VICE
  # test suites write $00 for success and $ff for failure.
  #
  # Wraps the SID's top mirror page, so every other access falls through.
  class DebugRegister
    ADDRESS = 0xd7ff

    def initialize(sid, &handler)
      @sid = sid
      @handler = handler
    end

    def peek(addr)
      @sid.peek(addr)
    end

    def poke(addr, value)
      return @handler.call(value) if addr == ADDRESS

      @sid.poke(addr, value)
    end
  end
end
