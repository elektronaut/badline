# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      # SIDEXTENDED 1.4 for the reSID engine: the state reSID keeps between
      # cycles, voice by voice. badline's SID follows reSID's model, so its
      # oscillators, noise registers and envelopes map across field by
      # field. x64sc won't load a snapshot without this module when it runs
      # reSID. A module another engine wrote has another layout, and isn't
      # read.
      module SIDExtended
        NAME = "SIDEXTENDED"
        MAJOR = 1
        MINOR = 4
        STATES = %i[attack decay_sustain release].freeze
        # What VICE's own snapshots carry for reSID's voice mask.
        VOICE_MASK = 0xf7

        # After the registers and the data bus, each field for the three
        # voices in turn: the part of the voice that keeps it, the variable
        # and its width.
        FIELDS = [
          %i[waveform @accumulator dword], %i[waveform @shift_register dword],
          %i[envelope @rate_counter word], %i[envelope @exponential_counter word],
          %i[envelope @counter byte], %i[envelope @state state], %i[envelope @hold_zero flag],
          %i[envelope @rate_period word], %i[envelope @exponential_period word],
          %i[envelope @envelope_pipeline byte], %i[waveform @shift_pipeline byte],
          %i[waveform @shift_register_reset dword], %i[waveform @floating_ttl dword], %i[waveform @pulse word]
        ].freeze

        module_function

        # `computer`'s SID must have caught up.
        def export(computer)
          sid = computer.sid
          voices = sid.instance_variable_get(:@voices)
          fields = FieldWriter.new.bytes(Array.new(0x20) { |reg| sid.register(reg) })
          fields.byte(sid.instance_variable_get(:@bus_value)).dword(sid.instance_variable_get(:@bus_ttl))
          FIELDS.each do |part, name, width|
            voices.each { |voice| write(fields, width, voice.public_send(part).instance_variable_get(name)) }
          end
          fields.byte(0).byte(0).byte(VOICE_MASK).section(NAME, MAJOR, MINOR)
        end

        def write(fields, width, value)
          return fields.byte(STATES.index(value)) if width == :state

          fields.public_send(width, value)
        end

        def import(section, computer)
          sid = computer.sid
          sid.send(:catch_up)
          fields = FieldReader.new(section).skip(0x20)
          sid.instance_variable_set(:@bus_value, fields.byte)
          sid.instance_variable_set(:@bus_ttl, fields.dword)
          voices = sid.instance_variable_get(:@voices)
          FIELDS.each do |part, name, width|
            voices.each { |voice| read(fields, voice.public_send(part), name, width) }
          end
          voices.each do |voice|
            voice.waveform.instance_variable_set(:@stale, true)
            voice.envelope.instance_variable_set(:@env3, voice.envelope.output)
          end
        end

        def read(fields, part, name, width)
          case width
          when :state then load_state(part, STATES.fetch(fields.byte, :release))
          when :flag then part.instance_variable_set(name, fields.flag?)
          else part.instance_variable_set(name, fields.public_send(width))
          end
        end

        def load_state(envelope, state)
          envelope.instance_variable_set(:@state, state)
          envelope.instance_variable_set(:@next_state, state)
        end
      end
    end
  end
end
