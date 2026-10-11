# frozen_string_literal: true

module Badline
  module Drives
    class Model1571
      class WD1770
        # The controller's registers, status and result in a keyed snapshot
        # module (BL-D8-FDC), and how many of the drive CPU's cycles until a
        # command under way finishes. It loads after the CPU, which that
        # counts from.
        def save_fields(out)
          out.ints("registers", @registers).int("status", @status).int("result", @result)
          out.int("due_in", @due - @cpu.cycles)
        end

        def load_fields(input)
          input.ints_into("registers", @registers)
          @status = input.byte("status", @status)
          @result = input.int("result", @result)
          @due = @cpu.cycles + input.int("due_in", @due - @cpu.cycles)
        end
      end

      class Bus
        # The drive's RAM and the byte last on its data bus, in a keyed
        # snapshot module (BL-D8-RAM).
        def save_fields(out)
          out.int("data", @data).bytes("ram", @ram.read(0, @ram.length))
        end

        def load_fields(input)
          @data = input.byte("data", @data)
          ram = @ram.read(0, @ram.length)
          @ram.write(0, input.bytes_into("ram", ram))
          @watching = false
        end
      end

      # The drive's own fields in a keyed snapshot module (BL-D8), as the
      # 1541's. The clock rate, the side and the fast serial direction come
      # from VIA 1's port A once the VIAs are loaded.
      module KeyedState
        def save_fields(out)
          settle!
          out.text("model", model_name).int("phase", @phase).int("cycles", @cycles)
          out.bool("so_pending", @mechanism.so_pending)
          @serial_port.save_fields(out, "serial.")
          out
        end

        def load_fields(input)
          settle!
          input.choice("model", [model_name], model_name)
          @phase = input.int("phase", @phase)
          @cycles = input.int("cycles", @cycles)
          @mechanism.so_pending = input.bool("so_pending", @mechanism.so_pending)
          @serial_port.load_fields(input, "serial.")
        end

        def restored!
          @fast_serial_out = @via1.port_a_output.anybits?(FAST_SERIAL_OUT)
          port_a_written(@via1.port_a_output)
          push_fast_output(@fast_serial_out ? fast_pins : 0)
          forget_orbits
        end

        # The drive as modules of its own, as the 1541's, with the CIA and
        # the WD1770.
        def save_modules(sections, name)
          sections << Snapshot::Keyed.section(name) { |out| save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-RAM") { |out| @bus.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-VIA1") { |out| @via1.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-VIA2") { |out| @via2.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-CIA") { |out| @cia.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-CPU") { |out| @cpu.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-FDC") { |out| @fdc.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-MECH") { |out| @mechanism.save_fields(out) }
          disk = @mechanism.disk
          sections << Snapshot::Keyed.section("#{name}-DISK") { |out| disk.save_fields(out) } if disk
          sections
        end

        # The drive from its modules, `input` being its own. The WD1770
        # counts from the CPU's cycles, so it loads after the CPU.
        def load_modules(modules, input, name)
          load_fields(input)
          @bus.load_fields(modules.required("#{name}-RAM"))
          @via1.load_fields(modules.required("#{name}-VIA1"))
          @via2.load_fields(modules.required("#{name}-VIA2"))
          @cia.load_fields(modules.required("#{name}-CIA"))
          @cpu.load_fields(modules.required("#{name}-CPU"))
          @fdc.load_fields(modules.required("#{name}-FDC"))
          disk = modules.optional("#{name}-DISK")
          mechanism = modules.required("#{name}-MECH")
          @mechanism.load_fields(mechanism,
                                 disk.nil? ? nil : Model1541::Disk.from_fields(disk, detached: modules.detached?))
          @via1.restored!
          @via2.restored!
          @cia.restored!
          @cpu.restored!
          restored!
        end
      end

      include KeyedState
    end
  end
end
