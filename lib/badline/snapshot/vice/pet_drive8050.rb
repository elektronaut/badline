# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # A true unit with an interface processor on device 8, as xpet 3.10,
        # xcbm2 and xcbm5x0 save it with true drive emulation: an 8050, an
        # 8250, an SFD-1001, a 4040, a 3040, a 2040, or a D9060 or D9090,
        # which xpet's type 9000 stands for. Each is DRIVE8 2.0 with the
        # unit's drives, DRIVE9 to DRIVE11 with none, DRIVECPU0 1.3, the
        # interface processor and its RAM, RIOT1D0 and RIOT2D0 0.0, its two
        # 6532s, and FDC0 0.0. xpet runs the floppy controller and the hard
        # disk's SASI host at a high level, so their processors, VIAs and
        # 6530s aren't in the snapshot: FDC0 holds the controller's state,
        # its last track in byte 6.
        #
        # DRIVE8 holds a block of 139 bytes for each of the unit's drives,
        # then 6 for the unit: each block has its head's half track, twice
        # the track, at $10 and the unit's type as a word at $28 (TYPES).
        # The 1001 and the hard disks have one block, and a hard disk's head
        # rests at HARD_DISK_TRACK. DRIVECPU0 is laid out as the 2031's
        # (Drive2031), its RAM the IP's page 0, the 6532s' 128 bytes each,
        # then the 4K of common RAM. A RIOT module holds port A's output and
        # direction registers, port B's, the edge control (bit 0 the PA7
        # interrupt, bit 1 a rising edge), the flags (bit 7 the timer's
        # interrupt, which xpet raises IRQ for, bit 6 PA7's), the timer's
        # counter, its divider as a word, two bytes xpet leaves 0, and
        # whether the timer interrupts.
        #
        # Written, once the controller, or the SASI host, is in its idle
        # loop between instructions (PET#settle_for_vice!): the IP's
        # registers and RAM, the 6532s, the heads' tracks, and FDC0 as xpet
        # leaves an idle controller with the track badline's controller last
        # stepped to. A unit whose controller is still busy is left out of
        # xpet's modules. Read: the IP's registers and RAM and the 6532s,
        # with the controller as a unit switched on has it in its idle loop,
        # its heads on track 1, from where its next job steps them. A job
        # under way in xpet's controller starts again from there. The disks
        # in the drives stay, and a hard disk's image with them, which also
        # says whether the unit is a D9060 or a D9090.
        module Drive8050
          UNIT = "DRIVE8"
          CPU = Drive2031::CPU
          RIOTS = %w[RIOT1D0 RIOT2D0].freeze
          FDC = "FDC0"
          NAMES = [UNIT, CPU, *RIOTS, FDC].freeze
          # xpet's drive types by DRIVE8's type word, for the units written
          # and read here.
          TYPES = { 0x1f72 => "8050", 0x203a => "8250", 0x03e9 => "1001", 0x0fc8 => "4040", 0x0be0 => "3040",
                    0x07f8 => "2040", 0x2328 => "9060" }.freeze
          # The type word each model is written with.
          WORDS = TYPES.invert.merge("9090" => 0x2328).freeze
          # The units that are hard disks, and the DOS 2.1 and DOS 1 units
          # on the 4040's board.
          HARD_DISKS = %w[9060 9090].freeze
          DOS2_BOARD = %w[4040 3040 2040].freeze
          # The drives each unit has, a block of DRIVE8 each.
          DRIVE_COUNTS = { "8050" => 2, "8250" => 2, "1001" => 1, "4040" => 2, "3040" => 2, "2040" => 2, "9060" => 1,
                           "9090" => 1 }.freeze
          # A drive's block in DRIVE8, and its fields.
          BLOCK = 0x8b
          HALF_TRACK = 0x10
          TYPE = 0x28
          # The half track xpet keeps a hard disk's head on.
          HARD_DISK_TRACK = 0x98
          # The unit's bytes after the drives' blocks.
          TAIL = 6
          # DRIVE8 as xpet saves an idle 8050, by the bytes that aren't 0,
          # but for the type and the drive count at COUNT: the first drive's
          # block, and from BLOCK on the second's with a byte past it.
          IDLE = { 0x00 => 0x01, 0x02 => 0x01, 0x0e => 0x01, 0x0f => 0x01, 0x10 => 0x4c, 0x1a => 0x01, 0x20 => 0x55,
                   0x30 => 0x06, 0x6f => 0xcd, 0x70 => 0xab, 0x71 => 0x34, 0x72 => 0x12 }.freeze
          IDLE_SECOND = { 0x0e => 0x01, 0x0f => 0x01, 0x10 => 0x24, 0x1a => 0x01, 0x20 => 0x55, 0x8f => 0x01 }.freeze
          COUNT = 0x01
          ZERO_PAGE = 0x80
          COMMON = 0x1000
          # FDC0 as xpet leaves an idle controller, and where the track goes.
          FDC_IDLE = [0x04, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00].freeze
          FDC_TRACK = 6
          # Where badline's controller keeps drive 0's track, in the 6530's
          # RAM: the 8050's, and the 4040's in the low six bits.
          TRACK_AT = 0x21
          DOS2_TRACK_AT = 0x03
          DOS2_TRACK = 0x3f
          DIVIDERS = [1, 8, 64, 1024].freeze
          IRQ_EDGE = 0x01
          RISING = 0x02
          TIMER_FLAG = 0x80
          PA7_FLAG = 0x40
          # The hard disk's controller, which holds the image's path.
          SASI = "BL-D8-SASI"

          module_function

          # Whether the snapshot has a true unit of these.
          def present?(container) = !container[FDC].nil? && !container[CPU].nil?

          def reads?(section)
            case section.name
            when CPU then Drive2031.reads?(section)
            when UNIT then section.major == Drive2031::DRIVE_MAJOR && section.minor == Drive2031::DRIVE_MINOR
            else section.major.zero? && section.minor.zero?
            end
          end

          # The model DRIVE8 names, or nil. Type 9000 reads as the D9060.
          def model(container)
            unit = container[UNIT]
            return nil if unit.nil? || unit.data.bytesize < BLOCK

            model = TYPES[FieldReader.new(unit).skip(TYPE).word]
            model if model && unit.data.bytesize >= size(model)
          end

          # Whether xpet saves the two models as one type.
          def same_type?(model, other) = WORDS.key?(model) && WORDS[model] == WORDS[other]

          def hard_disk?(model) = HARD_DISKS.include?(model)

          # The hard disk whose image the kept modules `disks` hold: a
          # D9090 for one with six heads, and otherwise a D9060.
          def hard_disk_model(disks)
            own = disks.find { |section| section.name == SASI }
            own && Keyed::Reader.parse(own).int("disk_heads", 4) == 6 ? "9090" : "9060"
          end

          # DRIVE8's size for the model.
          def size(model) = (BLOCK * DRIVE_COUNTS.fetch(model)) + TAIL

          # xpet's modules for the unit whose BL-D8 modules `readers` holds,
          # and none without one, or with its controller away from its idle
          # loop.
          def export(machine, readers)
            drive = readers["BL-D8"]
            model = drive&.text("model", "")
            return [] unless WORDS.key?(model) && idle?(model, readers)

            [unit(model, readers), *Drive2031::UNITS.drop(1).map { |name| none(name) },
             Drive2031.cpu_section(machine, readers.fetch("BL-D8-IPCPU"), ram(readers)),
             riot(RIOTS[0], readers.fetch("BL-D8-RIOT1")), riot(RIOTS[1], readers.fetch("BL-D8-RIOT2")),
             fdc(model, readers)]
          end

          # Whether both processors are between instructions, the
          # controller at the start of its idle loop.
          def idle?(model, readers)
            controller = readers.fetch(hard_disk?(model) ? "BL-D8-SASICPU" : "BL-D8-FDCCPU")
            !position?(controller) && !position?(readers.fetch("BL-D8-IPCPU")) &&
              controller.int("pc", 0) == controller_loop(model)
          end

          # Where the model's controller, or its SASI host, waits for jobs.
          def controller_loop(model)
            case model
            when "9060", "9090" then Drives::Model9060::Idle::SASI_LOOP
            when "2040" then Drives::Model2040::FDC_LOOP
            when "4040", "3040" then Drives::Model4040::FDC_LOOP
            else Drives::Model8050::Idle::FDC_LOOP
            end
          end

          def position?(cpu) = !cpu.text("pos.seq", "").empty?

          def unit(model, readers)
            count = DRIVE_COUNTS.fetch(model)
            bytes = Array.new(size(model), 0)
            IDLE.each { |offset, value| bytes[offset] = value }
            IDLE_SECOND.each { |offset, value| bytes[BLOCK + offset] = value } if count > 1
            bytes[COUNT] = count
            tracks = half_tracks(model, readers)
            count.times do |drive|
              at = BLOCK * drive
              bytes[at + HALF_TRACK] = tracks[drive]
              bytes[at + TYPE, 2] = [WORDS.fetch(model)].pack("v").bytes
            end
            FieldWriter.new.bytes(bytes).section(UNIT, Drive2031::DRIVE_MAJOR, Drive2031::DRIVE_MINOR)
          end

          # Each drive's head as xpet's half track: the 8050's cylinder on
          # from 1, the 4040's half track on from track 1, and a hard
          # disk's where xpet keeps it.
          def half_tracks(model, readers)
            return [HARD_DISK_TRACK] if hard_disk?(model)

            mechanism = readers.fetch("BL-D8-MECH")
            if DOS2_BOARD.include?(model)
              mechanism.ints("half_tracks", [0, 0]).map { |half_track| half_track + 2 }
            else
              mechanism.ints("cylinders", [0, 0]).map { |cylinder| (cylinder + 1) * 2 }
            end
          end

          def none(name) = Drive2031.unit(Drive2031::NONE, name)

          # The IP's RAM as xpet lays it out: page 0 from both 6532s, then
          # the common RAM.
          def ram(readers)
            [readers.fetch("BL-D8-RIOT1"), readers.fetch("BL-D8-RIOT2")].flat_map do |riot|
              filled(riot.bytes("ram", "".b).bytes, ZERO_PAGE)
            end + filled(readers.fetch("BL-D8-COMMON").bytes("ram", "".b).bytes, COMMON)
          end

          def filled(bytes, length) = Array.new(length) { |index| bytes[index] || 0 }

          def riot(name, input)
            edge = input.bool("edge_irq_enabled", false) ? IRQ_EDGE : 0
            edge |= RISING if input.bool("rising_edge", false)
            timer = input.bool("timer.flag", false) && input.bool("timer.irq_enabled", false)
            flags = (timer ? TIMER_FLAG : 0) | (input.bool("pa7_flag", false) ? PA7_FLAG : 0)
            divider = DIVIDERS.fetch(input.int("timer.interval", 0) & 0x03)
            fields = FieldWriter.new.byte(input.int("ora", 0)).byte(input.int("ddra", 0)).byte(input.int("orb", 0))
            fields.byte(input.int("ddrb", 0)).byte(edge).byte(flags).byte(input.int("timer.counter", 0)).word(divider)
            fields.zeros(2).flag(input.bool("timer.irq_enabled", false)).section(name, 0, 0)
          end

          # FDC0 with the controller's track, and a hard disk's with none.
          def fdc(model, readers)
            bytes = FDC_IDLE.dup
            unless hard_disk?(model)
              ram = readers.fetch("BL-D8-RRIOT").bytes("ram", "".b)
              bytes[FDC_TRACK] = if DOS2_BOARD.include?(model)
                                   ram.getbyte(DOS2_TRACK_AT).to_i & DOS2_TRACK
                                 else
                                   ram.getbyte(TRACK_AT).to_i
                                 end
            end
            FieldWriter.new.bytes(bytes).section(FDC, 0, 0)
          end

          # The unit's keyed modules, named for device 8, from the
          # snapshot's: the IP's side from xpet's, the controller's side
          # from `reference`, a unit's in its idle loop, and `disks`, the
          # drives' disk modules badline keeps, or a hard disk's controller
          # with its image.
          def import(container, reference, disks)
            cpu = container[CPU]
            page = FieldReader.new(cpu).skip(Drive2031::RAM_AT).string(ZERO_PAGE * 2)
            common = FieldReader.new(cpu).skip(Drive2031::RAM_AT + (ZERO_PAGE * 2)).string(COMMON)
            sections = [Keyed.section("BL-D8") { |out| unit_fields(container, reference, out) },
                        Keyed.section("BL-D8-COMMON") { |out| out.bytes("ram", common) },
                        riot_section("BL-D8-RIOT1", container[RIOTS[0]], page.byteslice(0, ZERO_PAGE)),
                        riot_section("BL-D8-RIOT2", container[RIOTS[1]], page.byteslice(ZERO_PAGE, ZERO_PAGE)),
                        Keyed.section("BL-D8-IPCPU") { |out| Drive2031.registers(cpu, out) }]
            sections + controller_side(reference, disks)
          end

          # The controller's side, which comes from a unit in its idle loop:
          # a floppy unit's, and a hard disk's SASI host.
          CONTROLLER = %w[BL-D8-FDCCPU BL-D8-VIA BL-D8-RRIOT BL-D8-MECH].freeze
          HOST = %w[BL-D8-SASICPU BL-D8-SASIRAM BL-D8-VIA].freeze

          def controller_side(reference, disks)
            base = reference.find { |section| section.name == SASI }
            return reference.select { |section| CONTROLLER.include?(section.name) } + disks if base.nil?

            reference.select { |section| HOST.include?(section.name) } + [controller(base, disks)]
          end

          # The hard disk's controller as `base` has it, with the image
          # badline's kept in `disks`.
          def controller(base, disks)
            kept = disks.find { |section| section.name == SASI }
            return base if kept.nil?

            target = Drives::Model9060::SASITarget.new
            target.load_fields(Keyed::Reader.parse(base))
            own = Keyed::Reader.parse(kept)
            path = own.text("path", "")
            if File.file?(path)
              target.disk = Storage::D90Image.new(path, read_only: own.bool("read_only", false),
                                                        heads: own.int("disk_heads", 4))
            end
            Keyed.section(SASI) { |out| target.save_fields(out) }
          end

          # The unit's own fields: its model and clock, with the controller's
          # last byte from `reference`, or a hard disk's SASI lines.
          def unit_fields(container, reference, out)
            own = Keyed::Reader.parse(reference.find { |section| section.name == "BL-D8" })
            model = own.text("model", "8050")
            out.text("model", model).int("phase", 0).int("cycles", FieldReader.new(container[CPU]).qword)
            return out.int("fdc_data", own.int("fdc_data", 0)) unless hard_disk?(model)

            out.int("sasi_data", own.int("sasi_data", 0)).bool("sasi.ack_high", own.bool("sasi.ack_high", true))
            out.bool("sasi.reset_high", own.bool("sasi.reset_high", false))
          end

          def riot_section(name, section, ram)
            fields = FieldReader.new(section)
            ora, ddra, orb, ddrb, edge, flags, counter = fields.bytes(7)
            divider = fields.word
            fields.skip(2)
            irq = fields.flag?
            Keyed.section(name) do |out|
              out.bytes("ram", ram).int("ora", ora).int("ddra", ddra).int("orb", orb).int("ddrb", ddrb)
              out.bool("edge_irq_enabled", edge.anybits?(IRQ_EDGE)).bool("rising_edge", edge.anybits?(RISING))
              out.bool("pa7_flag", flags.anybits?(PA7_FLAG)).int("timer.counter", counter)
              out.int("timer.interval", DIVIDERS.index(divider) || 0).int("timer.prescale", [divider, 1].max)
              out.bool("timer.flag", flags.anybits?(TIMER_FLAG)).bool("timer.expired", flags.anybits?(TIMER_FLAG))
              out.bool("timer.irq_enabled", irq)
            end
          end

          # A unit of `model` switched on and run into its controller's idle
          # loop, both processors between instructions, as keyed modules
          # named for device 8, run once a model.
          def reference(model)
            @references ||= {}
            @references[model] ||= booted(model)
          end

          def booted(model)
            unit = new_unit(model)
            unit.boot_cycles.times { unit.host_cycle! }
            unit.cycle! until unit.settled_for_vice?
            unit.save_modules([], "BL-D8")
          end

          def new_unit(model)
            case model
            when "8250" then Drives::Model8250.new
            when "1001" then Drives::Model1001.new
            when "4040" then Drives::Model4040.new
            when "3040" then Drives::Model3040.new
            when "2040" then Drives::Model2040.new
            when "9060" then Drives::Model9060.new
            when "9090" then Drives::Model9090.new
            else Drives::Model8050.new
            end
          end
        end
      end
    end
  end
end
