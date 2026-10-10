# frozen_string_literal: true

module Badline
  # The I/O port of the 6510 and the 8502 at $00 (direction) and $01
  # (data). An input pin reads its pull-up, P4 reads the datasette's sense
  # line, and a pin without a pull-up holds the charge last driven onto
  # it. P5 drives the datasette motor through an inverter: low runs it.
  #
  # The 6510 has pull-ups on P0-P2 and P4 and leaves P3, P6 and P7
  # floating. The 8502 adds a CAPS LOCK pin on P6, high while the key is
  # up.
  class CPUPort
    TAPE_SENSE = 0b0001_0000

    # The direction and output registers, and the charge on the floating
    # pins.
    attr_reader :ddr, :data, :floating

    # The port as the banking logic reads it (PortStatus).
    attr_reader :status

    # Whether CAPS LOCK is down, holding its pin low.
    attr_reader :caps_lock

    # +pullups+ and +floating+ are the masks of the pins with a pull-up and
    # of the floating ones, and +caps_lock+ the CAPS LOCK pin's, 0 where
    # there is none.
    def initialize(datasette, pullups:, floating:, caps_lock: 0)
      @datasette = datasette
      @pullups = pullups
      @floating_mask = floating
      @caps_lock_pin = caps_lock
      @caps_lock = false
      @ddr = 0x00
      @data = 0x00
      @floating = 0x00
      @change_handler = nil
      @status = PortStatus.new(%i[basic kernal io tape_out tape_switch tape_motor], value: input_value)
    end

    # Calls the block after every write to the port, for the bus to remap
    # its banks.
    def on_change(&handler)
      @change_handler = handler
    end

    # What a read of $01 sees.
    def value = @status.value

    def write_ddr(value)
      @ddr = value
      update
    end

    def write_data(value)
      @data = value
      update
    end

    # The RES line clears the direction and output registers. The floating
    # pins keep their charge.
    def reset!
      @ddr = 0x00
      @data = 0x00
      update
    end

    # Sets the registers and the charge, as a snapshot restores them, and
    # drives the motor and calls the change handler as a write does.
    def restore(ddr, data, floating)
      load(ddr, data, floating)
      update
    end

    # Sets the registers and the charge, as a snapshot loads them, without
    # driving the motor or calling the change handler.
    def load(ddr, data, floating)
      @ddr = ddr
      @data = data
      @floating = floating
      refresh
    end

    # Holds CAPS LOCK down, or lets it up.
    def caps_lock=(down)
      @caps_lock = down
      refresh
    end

    # Reads the inputs again, after the datasette's sense line changes.
    def refresh
      @status.value = input_value
    end

    private

    def update
      driven = @ddr & @floating_mask
      @floating = (@floating & ~driven) | (@data & driven)
      refresh
      @datasette.motor = !@status.tape_motor?
      @change_handler&.call
    end

    def input_value
      input = @pullups | (@floating & @floating_mask)
      input |= @caps_lock_pin unless @caps_lock
      input &= ~TAPE_SENSE if @datasette.sense_low?
      (@data & @ddr) | (input & ~@ddr & 0xff)
    end
  end
end
