# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # A true 8050, 8250 or SFD-1001 on device 8, as xpet 3.10, xcbm2
        # and xcbm5x0 save it with true drive emulation: DRIVE8 2.0 with the
        # unit's drives, DRIVE9 to DRIVE11 with none, DRIVECPU0 1.3, the interface processor and its RAM,
        # RIOT1D0 and RIOT2D0 0.0, its two 6532s, and FDC0 0.0. xpet runs
        # the floppy controller at a high level, so its 6504, VIA and 6530
        # aren't in the snapshot: FDC0 holds the controller's state, its
        # last track in byte 6.
        #
        # DRIVE8 holds a block of 139 bytes for each of the unit's drives,
        # then 6 for the unit: each block has its head's half track, twice
        # the track, at $10 and the unit's type as a word at $28 (TYPES).
        # DRIVECPU0 is laid out as the 2031's (Drive2031), its RAM the IP's
        # page 0, the 6532s' 128 bytes each, then the 4K of common RAM.
        # A RIOT module holds port A's output and direction registers, port
        # B's, the edge control (bit 0 the PA7 interrupt, bit 1 a rising
        # edge), the flags (bit 7 the timer's interrupt, which xpet raises
        # IRQ for, bit 6 PA7's), the timer's
        # counter, its divider as a word, two bytes xpet leaves 0, and
        # whether the timer interrupts.
        #
        # Written, once the controller is in its idle loop between
        # instructions (PET#settle_for_vice!): the IP's registers and RAM,
        # the 6532s, the heads' tracks, and FDC0 as xpet leaves an idle
        # controller with the track badline's controller last stepped to.
        # A unit whose controller is still busy is left out of xpet's
        # modules. Read: the IP's registers and RAM and the 6532s, with the
        # controller as a unit switched on has it in its idle loop, its
        # heads on track 1, from where its next job steps them. A job under
        # way in xpet's controller starts again from there. The disks in
        # the drives stay.
        module Drive8050
          UNIT = "DRIVE8"
          CPU = Drive2031::CPU
          RIOTS = %w[RIOT1D0 RIOT2D0].freeze
          FDC = "FDC0"
          NAMES = [UNIT, CPU, *RIOTS, FDC].freeze
          # xpet's drive types by DRIVE8's type word, for the units written
          # and read here.
          TYPES = { 0x1f72 => "8050", 0x203a => "8250", 0x03e9 => "1001" }.freeze
          # The drives each unit has, a block of DRIVE8 each.
          DRIVE_COUNTS = { "8050" => 2, "8250" => 2, "1001" => 1 }.freeze
          # A drive's block in DRIVE8, and its fields.
          BLOCK = 0x8b
          HALF_TRACK = 0x10
          TYPE = 0x28
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
          # RAM.
          TRACK_AT = 0x21
          DIVIDERS = [1, 8, 64, 1024].freeze
          IRQ_EDGE = 0x01
          RISING = 0x02
          TIMER_FLAG = 0x80
          PA7_FLAG = 0x40

          module_function

          # Whether the snapshot has a true 8050 or 8250.
          def present?(container) = !container[FDC].nil? && !container[CPU].nil?

          def reads?(section)
            case section.name
            when CPU then Drive2031.reads?(section)
            when UNIT then section.major == Drive2031::DRIVE_MAJOR && section.minor == Drive2031::DRIVE_MINOR
            else section.major.zero? && section.minor.zero?
            end
          end

          # The model DRIVE8 names, or nil.
          def model(container)
            unit = container[UNIT]
            return nil if unit.nil? || unit.data.bytesize < BLOCK

            model = TYPES[FieldReader.new(unit).skip(TYPE).word]
            model if model && unit.data.bytesize >= size(model)
          end

          # DRIVE8's size for the model.
          def size(model) = (BLOCK * DRIVE_COUNTS.fetch(model)) + TAIL

          # xpet's modules for the 8050 or 8250 whose BL-D8 modules `readers`
          # holds, and none without one, or with its controller away from
          # its idle loop.
          def export(machine, readers)
            drive = readers["BL-D8"]
            model = drive&.text("model", "")
            return [] unless TYPES.value?(model) && idle?(readers)

            [unit(model, readers.fetch("BL-D8-MECH")), *Drive2031::UNITS.drop(1).map { |name| none(name) },
             Drive2031.cpu_section(machine, readers.fetch("BL-D8-IPCPU"), ram(readers)),
             riot(RIOTS[0], readers.fetch("BL-D8-RIOT1")), riot(RIOTS[1], readers.fetch("BL-D8-RIOT2")),
             fdc(readers.fetch("BL-D8-RRIOT"))]
          end

          # Whether both processors are between instructions, the
          # controller at the start of its idle loop.
          def idle?(readers)
            fdc = readers.fetch("BL-D8-FDCCPU")
            !position?(fdc) && !position?(readers.fetch("BL-D8-IPCPU")) &&
              fdc.int("pc", 0) == Drives::Model8050::Idle::FDC_LOOP
          end

          def position?(cpu) = !cpu.text("pos.seq", "").empty?

          def unit(model, mechanism)
            count = DRIVE_COUNTS.fetch(model)
            bytes = Array.new(size(model), 0)
            IDLE.each { |offset, value| bytes[offset] = value }
            IDLE_SECOND.each { |offset, value| bytes[BLOCK + offset] = value } if count > 1
            bytes[COUNT] = count
            cylinders = mechanism.ints("cylinders", [0, 0])
            count.times do |drive|
              at = BLOCK * drive
              bytes[at + HALF_TRACK] = ((cylinders[drive] || 0) + 1) * 2
              bytes[at + TYPE, 2] = [TYPES.key(model)].pack("v").bytes
            end
            FieldWriter.new.bytes(bytes).section(UNIT, Drive2031::DRIVE_MAJOR, Drive2031::DRIVE_MINOR)
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

          def fdc(rriot)
            bytes = FDC_IDLE.dup
            bytes[FDC_TRACK] = rriot.bytes("ram", "".b).getbyte(TRACK_AT).to_i
            FieldWriter.new.bytes(bytes).section(FDC, 0, 0)
          end

          # The unit's keyed modules, named for device 8, from the
          # snapshot's: the IP's side from xpet's, the controller's side
          # from `reference`, a unit's in its idle loop, and `disks`, the
          # drives' disk modules badline keeps.
          def import(container, reference, disks)
            cpu = container[CPU]
            page = FieldReader.new(cpu).skip(Drive2031::RAM_AT).string(ZERO_PAGE * 2)
            common = FieldReader.new(cpu).skip(Drive2031::RAM_AT + (ZERO_PAGE * 2)).string(COMMON)
            sections = [Keyed.section("BL-D8") { |out| unit_fields(container, reference, out) },
                        Keyed.section("BL-D8-COMMON") { |out| out.bytes("ram", common) },
                        riot_section("BL-D8-RIOT1", container[RIOTS[0]], page.byteslice(0, ZERO_PAGE)),
                        riot_section("BL-D8-RIOT2", container[RIOTS[1]], page.byteslice(ZERO_PAGE, ZERO_PAGE)),
                        Keyed.section("BL-D8-IPCPU") { |out| Drive2031.registers(cpu, out) }]
            sections + reference.select { |section| CONTROLLER.include?(section.name) } + disks
          end

          # The controller's side, which comes from a unit in its idle loop.
          CONTROLLER = %w[BL-D8-FDCCPU BL-D8-VIA BL-D8-RRIOT BL-D8-MECH].freeze

          def unit_fields(container, reference, out)
            own = Keyed::Reader.parse(reference.find { |section| section.name == "BL-D8" })
            out.text("model", own.text("model", "8050")).int("phase", 0)
            out.int("cycles", FieldReader.new(container[CPU]).qword).int("fdc_data", own.int("fdc_data", 0))
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
            unit = case model
                   when "8250" then Drives::Model8250.new
                   when "1001" then Drives::Model1001.new
                   else Drives::Model8050.new
                   end
            unit.boot_cycles.times { unit.host_cycle! }
            unit.cycle! until idle_loop?(unit)
            unit.save_modules([], "BL-D8")
          end

          def idle_loop?(unit)
            cpu = unit.fdc_cpu
            unit.ip_cpu.boundary? && cpu.boundary? && cpu.program_counter == Drives::Model8050::Idle::FDC_LOOP
          end
        end
      end
    end
  end
end
