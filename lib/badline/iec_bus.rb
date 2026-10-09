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
  #
  # Fast serial adds SRQ, which the C64 leaves alone. A C128 and a 1571
  # clock bytes over it from a CIA's CNT, with the bits on DATA from its
  # SP, through buffers each side turns towards the bus to send. A pin low
  # pulls its line low. Each side pushes the lines it pulls when they
  # move: the host through host_fast_lines=, which tells the drives
  # (fast_lines_moved), and a drive through drives_fast_moved!, which
  # tells the host (on_fast_change).
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

    # The lines pulled low, as ATN, CLK, DATA and SRQ bits
    ATN = 0x01
    CLK = 0x02
    DATA = 0x04
    SRQ = 0x08

    # A drive's serial_output bits above VIA 1's port B: its fast serial
    # pins pulling DATA and SRQ.
    DRIVE_FAST_DATA = 0x100
    DRIVE_FAST_SRQ = 0x200

    attr_reader :drives, :host_lines

    # The lines the host's fast serial pins pull, as DATA and SRQ bits.
    attr_reader :host_fast_lines

    def initialize
      @drives = []
      @host_lines = 0
      @host_fast_lines = 0
      @drive_fast_lines = 0
      @on_fast_change = nil
    end

    # The host's fast serial pins moved: +low+ is the lines they pull, as
    # DATA and SRQ bits.
    def host_fast_lines=(low)
      return if low == @host_fast_lines

      @host_fast_lines = low
      @drives.each(&:fast_lines_moved)
    end

    # A drive's fast serial pins moved (serial_output's fast bits).
    def drives_fast_moved!
      low = 0
      @drives.each do |drive|
        output = drive.serial_output
        low |= DATA if output.anybits?(DRIVE_FAST_DATA)
        low |= SRQ if output.anybits?(DRIVE_FAST_SRQ)
      end
      return if low == @drive_fast_lines

      @drive_fast_lines = low
      @on_fast_change&.call
    end

    # Calls the block whenever the drives move their fast serial pins.
    def on_fast_change(&block)
      @on_fast_change = block
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
    # than one line, SRQ included. +host+ is the C64's port A lines as the
    # reader sees them, which a drive takes a cycle late (see
    # Drive::SerialLines).
    def low_lines(host = @host_lines)
      atn = host.anybits?(HOST_ATN_OUT)
      low = @host_fast_lines | @drive_fast_lines
      low |= ATN if atn
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
