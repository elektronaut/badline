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
      end

      include KeyedState
    end
  end
end
