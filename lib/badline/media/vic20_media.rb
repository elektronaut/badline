# frozen_string_literal: true

module Badline
  module Media
    # Media on a VIC-20. A program loads once the KERNAL has booted: a
    # BASIC program at the start of BASIC, wherever the RAM puts it, and
    # RUNs. A program that loads into BLK5 at $A000 is a cartridge's ROM
    # instead, as are the parts of a set that includes one
    # (Vic20Cartridge), and goes in with a power cycle, as a .crt does.
    # Disks mount on device 8 through the KERNAL traps, or go in a true
    # 1541 (TrueDrive), and tapes play on the datasette.
    module Vic20Media
      # The expansions that fill BLK1, BLK2 and BLK3 one block after
      # another, each with the last address it fills.
      BLOCK_EXPANSIONS = [[0x3fff, :"8k"], [0x5fff, :"16k"], [0x7fff, :"24k"]].freeze

      # What a VIC-20 doesn't take.
      UNSUPPORTED = %w[.sid].freeze

      # The platform byte of a VIC-20 tape (Storage::TAP#platform).
      TAPE_PLATFORM = 1

      class << self
        def attach(machine, path, autostart:, **options)
          extension = File.extname(path).downcase
          raise ArgumentError, "#{path} doesn't go in a VIC-20" if UNSUPPORTED.include?(extension)

          if TrueDrive.takes?(machine, path)
            attach_true_drive(machine, path, options.fetch(:disk, {}), autostart:)
          elsif File.directory?(path)
            machine.mount(Storage::HostDirectory.new(path))
            "Mounted #{path} as device 8"
          elsif extension == ".crt"
            attach_cartridge(machine, path, Storage::CRTFile.new(path, machine: :vic20).chips)
          elsif extension == ".tap"
            attach_tape(machine, path, autostart:)
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
            Vic20Basic::BASIC_STARTS.fetch(load_addr, :unexpanded)
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
          elsif File.file?(path) && !%w[.sid .crt .tap .g64].include?(extension)
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

        # A tape made for another machine plays all the same, and says so.
        def attach_tape(machine, path, autostart:)
          tape = Storage::TAP.new(path)
          machine.datasette.insert(tape)
          machine.datasette.play!
          machine.type_text(TAPE_AUTOSTART) if autostart
          message = "Inserted #{path} in the datasette"
          tape.platform == TAPE_PLATFORM ? message : "#{message}, a tape for another machine than the VIC-20"
        end

        def attach_true_drive(machine, path, disk, autostart:)
          message = TrueDrive.insert(machine, path, read_only: disk.fetch(:read_only, false))
          machine.type_text(disk_autostart(first_program(path))) if autostart
          message
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
          basic = data && data.length > 2 && Vic20Basic::BASIC_STARTS.key?(data[0] | (data[1] << 8))
          basic ? %(lO"*",8\rrun\r) : AUTOSTART
        end

        def attach_prg(machine, path, autostart:)
          bytes = Vic20Cartridge.program_bytes(path)
          chips = Vic20Cartridge.chips(path, bytes)
          return attach_cartridge(machine, path, chips) if chips

          machine.on_init { Vic20Basic.load_program(machine, bytes, autostart:) }
          "Loading #{path}"
        end
      end
    end
  end
end
