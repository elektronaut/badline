# frozen_string_literal: true

module Badline
  module Drives
    class Model9060
      class SASITarget
        # The controller's fields in a keyed snapshot module (BL-D8-SASI):
        # the bus phase, REQ, the cycles left to the next, the command, the
        # bytes of the phase and the place in them, the write under way,
        # the sense bytes, the fast mode, its clock, the heads' cylinder, the
        # geometry and the block buffer, then the image's path and how it
        # was opened. The image itself stays in its file, which each write
        # reached as it ended.
        module KeyedState
          def save_fields(out)
            out.int("phase", @phase).bool("request", @request).int("delay", @delay)
            out.ints("command", @command).ints("buffer", @buffer).int("index", @index)
            out.bool("writing", @writing).ints("sense", @sense).ints("last_sense", @last_sense)
            out.bool("fast", @fast).int("cycle", @cycle).int("cylinder", @cylinder)
            out.int("heads", @heads).int("sectors", @sectors).ints("block_buffer", @block_buffer)
            disk = @disk
            out.text("path", disk.nil? ? "" : disk.path.to_s).bool("read_only", disk.nil? || disk.read_only?)
            out.int("disk_heads", disk.nil? ? 0 : disk.heads)
          end

          # A detached reader, or a host file that is gone, leaves the drive
          # empty.
          def load_fields(input, detached: false)
            load_bus_fields(input)
            path = input.text("path", "")
            read_only = input.bool("read_only", false)
            heads = input.int("disk_heads", 4)
            @disk = detached || !File.file?(path) ? nil : Storage::D90Image.new(path, read_only:, heads:)
          end

          private

          def load_bus_fields(input)
            @phase = input.int("phase", @phase)
            @request = input.bool("request", @request)
            @delay = input.int("delay", @delay)
            @command = input.ints("command", @command).dup
            @buffer = input.ints("buffer", @buffer).dup
            @index = input.int("index", @index)
            @writing = input.bool("writing", @writing)
            @sense = input.ints("sense", @sense).dup
            @last_sense = input.ints("last_sense", @last_sense).dup
            @fast = input.bool("fast", @fast)
            @cycle = input.int("cycle", @cycle)
            @cylinder = input.int("cylinder", @cylinder)
            @heads = input.int("heads", @heads)
            @sectors = input.int("sectors", @sectors)
            @block_buffer = input.ints("block_buffer", @block_buffer).dup
          end
        end

        include KeyedState
      end

      # The unit's own fields in a keyed snapshot module (BL-D8): its model,
      # its clock phase and cycle count, each bus's last byte, the
      # controller's lines as the port latched them, under ieee.*, and the
      # SASI lines' ACK and RST levels. A save settles the unit first, so it
      # is awake; a load finds its passes afresh.
      module KeyedState
        def save_fields(out)
          settle!
          out.text("model", model_name).int("phase", @phase).int("cycles", @cycles)
          out.int("ip_data", @ip_bus.data).int("sasi_data", @sasi_bus.data)
          out.int("ieee.host", @ieee_port.host)
          ack_high, reset_high = @lines.state
          out.bool("sasi.ack_high", ack_high).bool("sasi.reset_high", reset_high)
          out
        end

        def load_fields(input)
          settle!
          input.choice("model", [model_name], model_name)
          @phase = input.int("phase", @phase)
          @cycles = input.int("cycles", @cycles)
          @ip_bus.data = input.byte("ip_data", @ip_bus.data)
          @sasi_bus.data = input.byte("sasi_data", @sasi_bus.data)
          @ieee_port.host = input.int("ieee.host", @ieee_port.host)
          @lines.state = [input.bool("sasi.ack_high", true), input.bool("sasi.reset_high", false)]
        end

        # The unit as modules of its own, named from `name` (BL-D8 for
        # device 8): its own fields, the common RAM, UC1 and UE1 with their
        # RAM, each processor, the host's RAM and VIA, and the hard disk's
        # controller.
        def save_modules(sections, name)
          sections << Snapshot::Keyed.section(name) { |out| save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-COMMON") { |out| @common.save_fields(out, "ram") }
          sections << Snapshot::Keyed.section("#{name}-RIOT1") { |out| @data_riot.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-RIOT2") { |out| @control_riot.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-IPCPU") { |out| @ip_cpu.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-SASICPU") { |out| @sasi_cpu.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-SASIRAM") { |out| @sasi_bus.ram.save_fields(out, "ram") }
          sections << Snapshot::Keyed.section("#{name}-VIA") { |out| @via.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-SASI") { |out| @target.save_fields(out) }
        end

        # The unit from its modules, `input` being its own.
        def load_modules(modules, input, name)
          load_fields(input)
          @common.load_fields(modules.required("#{name}-COMMON"), "ram")
          @data_riot.load_fields(modules.required("#{name}-RIOT1"))
          @control_riot.load_fields(modules.required("#{name}-RIOT2"))
          @ip_cpu.load_fields(modules.required("#{name}-IPCPU"))
          @sasi_cpu.load_fields(modules.required("#{name}-SASICPU"))
          @sasi_bus.ram.load_fields(modules.required("#{name}-SASIRAM"), "ram")
          @via.load_fields(modules.required("#{name}-VIA"))
          @target.load_fields(modules.required("#{name}-SASI"), detached: modules.detached?)
          @via.restored!
          @ip_cpu.restored!
          @sasi_cpu.restored!
        end
      end

      include KeyedState
    end
  end
end
