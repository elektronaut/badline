# frozen_string_literal: true

require "badline/drives/model8050"

module Badline
  module Drives
    # The SFD-1001: the 8250LP's board redrawn as one PCB with one
    # double-sided drive, a Matsushita JU-570-2 (schematic 251406). Both
    # processors see an 8250. The interface processor runs DOS 2.7, which
    # doesn't know there is one drive, and the controller runs 251257-02A
    # from the EPROM on its 6530 adaptor (251252-01): the 8250LP's program
    # with an interrupt every 3 ms for the JU-570's step rate, a longer head
    # settle, and every job for drive 1 ended with an error. Drive 1's
    # stepper, motor and LED aren't wired, so the unit takes no disk there,
    # and its LED never lights.
    class Model1001 < Model8250
      # The LED bit of drive 1, which the board leaves unwired.
      DRIVE1_LED = 0x01

      def model_name = "1001"

      # +fdc_rom+ defaults to 251257-02A, the rest as Model8050's.
      def initialize(dos_rom: nil, fdc_rom: nil, host_clock_hz: CLOCK_HZ, device: 8)
        super(dos_rom:, fdc_rom: fdc_rom || ROM.read("1001/fdc-251257-02a.rom"), host_clock_hz:, device:)
      end

      def leds = super & ~DRIVE1_LED

      # Puts a Disk in drive 0, the only one. Drive 1 raises ArgumentError.
      def insert(disk, drive: 0)
        raise ArgumentError, "the 1001 has one drive, not drive #{drive}" unless drive.zero?

        super
      end
    end
  end
end
