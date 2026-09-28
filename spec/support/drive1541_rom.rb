# frozen_string_literal: true

# A 16 KB stand-in for the DOS ROM at $C000-$FFFF: NOPs, with the reset
# and IRQ vectors pointing into drive RAM.
module Drive1541ROM
  module_function

  def stub(reset: 0x0300, irq: 0x0400)
    bytes = Array.new(0x4000, 0xea)
    bytes[0x3ffc, 4] = [reset & 0xff, reset >> 8, irq & 0xff, irq >> 8]
    Badline::ROM.new(bytes, length: 0x4000, start: 0xc000)
  end
end
