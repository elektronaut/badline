# frozen_string_literal: true

module Badline
  # The serial bus between the C64 and its drives: ATN, CLK and DATA, each
  # an open-collector line with a pull-up. A line is low while any device
  # pulls it (wired-AND), and high otherwise. Every read works the levels
  # out from what each side drives now.
  #
  # The C64 drives the lines from CIA 2's port A through 7406 inverters, so
  # an output bit of 1 pulls its line low: PA3 ATN, PA4 CLK and PA5 DATA.
  # The machine pushes those bits into the bus (host_lines=), which holds
  # them. PA6 and PA7 read CLK and DATA directly, 1 for a released line.
  # The bus stands in as CIA 2's peripheral for those two inputs.
  #
  # A drive drives CLK and DATA from VIA 1's PB3 and PB1, the same way. It
  # also pulls DATA while ATN IN differs from its ATN acknowledge on PB4
  # (an XOR gate), which answers ATN in hardware before the DOS gets to it.
  # SerialPort reads the lines back into VIA 1.
  class IECBus
    # CIA 2 port A
    HOST_ATN_OUT = 0x08
    HOST_CLK_OUT = 0x10
    HOST_DATA_OUT = 0x20
    HOST_CLK_IN = 0x40
    HOST_DATA_IN = 0x80

    # VIA 1 port B
    DRIVE_DATA_OUT = 0x02
    DRIVE_CLK_OUT = 0x08
    DRIVE_ATNA = 0x10

    # The lines pulled low, as ATN, CLK and DATA bits
    ATN = 0x01
    CLK = 0x02
    DATA = 0x04

    attr_reader :drives, :host_lines

    def initialize
      @drives = []
      @host_lines = 0
    end

    # The machine pushes the lines it pulls, as port A bits, whenever they
    # may have moved: its output bits, with input bits floating high as the
    # 7406 inputs see them. A bus with only drives on it keeps 0.
    def host_lines=(lines)
      @host_lines = lines
      @drives.each(&:host_written!)
    end

    def attach(drive)
      @drives << drive unless @drives.include?(drive)
    end

    def detach(drive)
      @drives.delete(drive)
    end

    # One pass over everything on the bus, for a reader that wants more
    # than one line. +host+ is the C64's port A lines as the reader sees
    # them, which a drive takes a cycle late (see Drive1541::SerialPort).
    def low_lines(host = @host_lines)
      atn = host.anybits?(HOST_ATN_OUT)
      low = atn ? ATN : 0
      low |= CLK if host.anybits?(HOST_CLK_OUT)
      low |= DATA if host.anybits?(HOST_DATA_OUT)
      i = 0
      while i < @drives.length
        drive = @drives[i].serial_output
        low |= CLK if drive.anybits?(DRIVE_CLK_OUT)
        low |= DATA if drive.anybits?(DRIVE_DATA_OUT) || atn != drive.anybits?(DRIVE_ATNA)
        i += 1
      end
      low
    end

    def atn_low?(host = @host_lines) = host.anybits?(HOST_ATN_OUT)

    def clk_low? = low_lines.anybits?(CLK)

    def data_low? = low_lines.anybits?(DATA)

    # CIA 2's port A pins as the bus leaves them: CLK IN and DATA IN low
    # while their lines are.
    def read_a(_port_a, _port_b)
      low = low_lines
      value = 0xff
      value &= ~HOST_CLK_IN if low.anybits?(CLK)
      value &= ~HOST_DATA_IN if low.anybits?(DATA)
      value
    end

    # Port B goes to the user port, not the serial bus.
    def read_b(_port_a, _port_b) = 0xff
  end
end
