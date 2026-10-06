# frozen_string_literal: true

module Badline
  module Media
    # Media on a VIC-20. A program loads once the KERNAL has booted: a
    # BASIC program at the start of BASIC, wherever the RAM puts it, and
    # RUNs. A program that loads into BLK5 at $A000 is a cartridge's ROM
    # instead, as are the parts of a set that includes one
    # (Vic20Cartridge), and goes in with a power cycle, as a .crt does.
    # Disks mount on device 8 through the KERNAL traps.
    module Vic20Media
      # Where BASIC starts with each RAM expansion it can start in, as
      # TXTTAB holds it.
      BASIC_STARTS = { 0x1001 => :unexpanded, 0x0401 => :"3k", 0x1201 => :"8k" }.freeze

      # The expansions that fill BLK1, BLK2 and BLK3 one block after
      # another, each with the last address it fills.
      BLOCK_EXPANSIONS = [[0x3fff, :"8k"], [0x5fff, :"16k"], [0x7fff, :"24k"]].freeze

      # What a VIC-20 doesn't take yet.
      UNSUPPORTED = %w[.sid .tap .g64].freeze

      class << self
        def attach(machine, path, autostart:, **options)
          extension = File.extname(path).downcase
          raise ArgumentError, "#{path} doesn't go in a VIC-20 yet" if UNSUPPORTED.include?(extension)

          if File.directory?(path)
            machine.mount(Storage::HostDirectory.new(path))
            "Mounted #{path} as device 8"
          elsif extension == ".crt"
            attach_cartridge(machine, path, Storage::CRTFile.new(path, machine: :vic20).chips)
          elsif MOUNT_TYPES.key?(extension)
            attach_storage(machine, path, options.fetch(:disk, {}), autostart:)
          else
            attach_prg(machine, path, autostart:)
          end
        end

        # The RAM expansion (Vic20::Bus::RAM_CONFIGURATIONS) a VIC-20 needs
        # for the program at `path`, or for the first program on the disk
        # or in the directory there, by where it loads. A BASIC program
        # needs the expansion its start of BASIC comes with, and more of
        # BLK1 to BLK3 when it runs past $3FFF. So does a machine-language
        # program loading into those blocks. Anything else, cartridges
        # included, runs unexpanded.
        def ram_for(path)
          data = first_program(path)
          return :unexpanded unless data && data.length > 2 && !Vic20Cartridge.chips(path, data)

          load_addr = data[0] | (data[1] << 8)
          if load_addr == 0x1201 || load_addr.between?(0x2000, 0x7fff)
            expansion_reaching(load_addr + data.length - 3)
          else
            BASIC_STARTS.fetch(load_addr, :unexpanded)
          end
        end

        private

        def expansion_reaching(last)
          BLOCK_EXPANSIONS.each { |reach, ram| return ram if last <= reach }
          BLOCK_EXPANSIONS.last.last
        end

        def first_program(path)
          extension = File.extname(path).downcase
          if File.directory?(path) || MOUNT_TYPES.key?(extension)
            open_storage(path).read_file("*")
          elsif File.file?(path) && !UNSUPPORTED.include?(extension) && extension != ".crt"
            Vic20Cartridge.program_bytes(path)
          end
        end

        def open_storage(path, disk = {})
          return Storage::HostDirectory.new(path) if File.directory?(path)

          storage = MOUNT_TYPES.fetch(File.extname(path).downcase)
          storage < Storage::DiskImage ? storage.new(path, **disk) : storage.new(path)
        end

        def attach_cartridge(machine, path, chips)
          machine.attach_cartridge(chips)
          "Attached cartridge #{path}"
        end

        def attach_storage(machine, path, disk, autostart:)
          storage = open_storage(path, disk)
          machine.mount(storage)
          machine.type_text(disk_autostart(storage.read_file("*"))) if autostart
          "Mounted #{path} as device 8"
        end

        # A BASIC program loads relocated to the start of BASIC, and anything
        # else where it says.
        def disk_autostart(data)
          basic = data && data.length > 2 && BASIC_STARTS.key?(data[0] | (data[1] << 8))
          basic ? %(lO"*",8\rrun\r) : AUTOSTART
        end

        def attach_prg(machine, path, autostart:)
          bytes = Vic20Cartridge.program_bytes(path)
          chips = Vic20Cartridge.chips(path, bytes)
          return attach_cartridge(machine, path, chips) if chips

          machine.on_init { start_prg(machine, bytes, autostart:) }
          "Loading #{path}"
        end

        # A BASIC program, one that loads at a start of BASIC or a byte
        # ahead of it, goes to this machine's start of BASIC. Anything else
        # goes where it says, and doesn't RUN.
        def start_prg(machine, data, autostart:)
          load_addr = data[0] | (data[1] << 8)
          start = machine.basic_start
          ahead = [0, 1].find { |offset| BASIC_STARTS.key?(load_addr + offset) || load_addr + offset == start }
          return machine.load_prg(data) unless ahead

          load_basic(machine, data, start - ahead, load_addr)
          machine.type_text("run\r") if autostart
        end

        # Puts a BASIC program at `address`, relinking its lines when that
        # isn't where it was saved from, as BASIC's LOAD does, and sets the
        # end of the program, where BASIC's variables start, and the end
        # address the KERNAL's LOAD leaves.
        def load_basic(machine, data, address, saved_at)
          ram = machine.ram
          ram.write(address, data[2..])
          end_addr = address + data.length - 2
          relink(ram, machine.basic_start, end_addr) unless address == saved_at
          [0x2d, 0xae].each { |pointer| ram.write(pointer, [end_addr & 0xff, end_addr >> 8]) }
        end

        # Points each line's link at the line after it, as BASIC's LINKPRG
        # does: past the zero that ends the line's text. A link with a zero
        # high byte ends the program.
        def relink(ram, line, end_addr)
          while line + 4 < end_addr && ram.peek(line + 1).positive?
            following = line + 4
            following += 1 while following < end_addr && ram.peek(following).positive?
            following += 1
            ram.write(line, [following & 0xff, following >> 8])
            line = following
          end
        end
      end
    end
  end
end
