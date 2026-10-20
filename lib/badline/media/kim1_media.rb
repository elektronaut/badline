# frozen_string_literal: true

module Badline
  module Media
    # What a KIM-1 loads (Media.attach): a MOS papertape, a .ptp or .pap
    # (Storage::Papertape), at the addresses its records give, or a .bin
    # of bare bytes, which says nothing of where it goes, at its Loading's
    # load address.
    #
    # Once the monitor runs, the bytes go straight into memory, after
    # the NMI and IRQ vectors at $17FA and $17FE, which nothing sets at
    # power-on, are pointed at the monitor's $1C00, so ST and BRK stop
    # the program and show where (User Manual, section 4.1). A papertape
    # can go in through the teletype instead, as the monitor's L command
    # reads it, in real time. The program then starts at its Loading's
    # start address, or else where it loads, as the user would start it:
    # AD, the address and GO on the keypad, or the address, a space and G
    # on the teletype. Without autostart the monitor stops at the
    # address.
    #
    # A .wav, a recording of a KIM tape (Storage::KIMTape), goes in the
    # cassette deck, for the monitor's LOADT to read once PLAY is down.
    module KIM1Media
      PAPERTAPES = Extensions.of(%i[papertape])

      # A .bin, bare bytes.
      BINARY = ".bin"

      # A recording of a tape.
      TAPE = ".wav"

      # What a KIM-1 takes.
      EXTENSIONS = (PAPERTAPES + [BINARY, TAPE]).freeze

      # Where a .bin loads without a load address, as most of the First
      # Book of KIM's programs do.
      DEFAULT_LOAD_ADDRESS = 0x0200

      # Where the monitor saves the registers and shows the PC, for the
      # NMI and IRQ vectors.
      MONITOR = 0x1c00

      NMI_VECTOR = 0x17fa
      IRQ_VECTOR = 0x17fe

      # How a KIM-1 loads and starts a program: at `load_address`, a .bin's,
      # or -1 for DEFAULT_LOAD_ADDRESS, from `start_address`, or -1 for
      # where it loads, and through the teletype's L command if
      # `teletype`.
      class Loading
        attr_reader :load_address, :start_address

        def initialize(load_address: -1, start_address: -1, teletype: false)
          @load_address = load_address
          @start_address = start_address
          @teletype = teletype
        end

        def teletype? = @teletype
      end

      # Loads straight into memory, from where it loads.
      DIRECT = Loading.new

      class << self
        # The Loading the command line's `options` ask for, with
        # --load-address, --start-address and --tty-load.
        def loading(options)
          load_address = options.load_address
          start_address = options.start_address
          Loading.new(load_address: load_address.nil? ? -1 : load_address,
                      start_address: start_address.nil? ? -1 : start_address, teletype: options.tty_load?)
        end

        # Whether a KIM-1 takes the file at `path`.
        def takes?(path) = EXTENSIONS.include?(File.extname(path).downcase)

        # Loads the program at `path` into the KIM-1 `machine` as
        # `loading` says, and starts it if `autostart`. Raises
        # Machine::Unsupported when it loads outside the RAM.
        def attach(machine, path, loading, autostart:)
          raise Machine::Unsupported, "doesn't go in a KIM-1" unless takes?(path)
          return insert_tape(machine, path) if File.extname(path).downcase == TAPE

          papertape = PAPERTAPES.include?(File.extname(path).downcase)
          tape = papertape ? Storage::Papertape.read(path) : nil
          records = tape.nil? ? [binary(path, loading.load_address)] : tape.records
          refuse_outside_ram(machine, records)
          start = loading.start_address.negative? ? records.first.address : loading.start_address
          if !tape.nil? && loading.teletype? && machine.tty?
            machine.teletype.type("L#{tape.text}")
          else
            machine.on_init { deposit(machine, records) }
          end
          machine.on_init { machine.type_text(start_keys(machine, start, autostart)) }
          "Loading #{path} at $#{hex(records.first.address)}"
        end

        private

        def insert_tape(machine, path)
          machine.tape.insert_tape(Storage::KIMTape.read(path))
          "Inserted #{path} in the tape deck"
        end

        def binary(path, load_address)
          Storage::Papertape::Record.new(load_address.negative? ? DEFAULT_LOAD_ADDRESS : load_address,
                                         File.binread(path).bytes)
        end

        def refuse_outside_ram(machine, records)
          records.each do |record|
            address = record.address
            last = address + record.bytes.size - 1
            raise Machine::Unsupported, "has no bytes to load" if last < address
            next if last <= 0xffff && (address..last).all? { |byte_address| machine.bus.ram?(byte_address) }

            raise Machine::Unsupported, "loads at $#{hex(address)}-$#{hex(last)}, outside the KIM-1's " \
                                        "#{machine.bus.ram_kb}K of RAM; --ram 5k or --ram expanded adds more"
          end
        end

        def deposit(machine, records)
          [NMI_VECTOR, IRQ_VECTOR].each do |vector|
            machine.poke(vector, MONITOR & 0xff)
            machine.poke(vector + 1, MONITOR >> 8)
          end
          records.each do |record|
            address = record.address
            record.bytes.each_with_index { |byte, offset| machine.poke(address + offset, byte) }
          end
        end

        # What starts the program at `start`, or stops at it without
        # `autostart`.
        def start_keys(machine, start, autostart)
          if machine.tty?
            opened = "#{hex(start)} "
            return autostart ? "#{opened}G" : opened
          end

          keys = "AD #{hex(start).chars.join(' ')}"
          autostart ? "#{keys} GO" : keys
        end

        def hex(value) = value.to_s(16).upcase.rjust(4, "0")
      end
    end
  end
end
