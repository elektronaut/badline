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
      #
      # After the 32 registers, the data bus byte and its countdown, each
      # field is written for the three voices in turn: the phase, the noise
      # register, the envelope's rate and exponential counters, its level,
      # state and hold-at-zero flag, its rate and exponential periods and
      # pipeline, then the noise register's shift pipeline and reset
      # countdown, the floating output's countdown and the pulse level. The
      # voice mask and two bytes before it end the module.
      module SIDExtended
        NAME = "SIDEXTENDED"
        MAJOR = 1
        MINOR = 4
        WAVEFORM_FIELDS = 6
        ENVELOPE_FIELDS = 8
        # What VICE's own snapshots carry for reSID's voice mask.
        VOICE_MASK = 0xf7

        # Each field's width, and where it sits among a voice's oscillator
        # fields (Waveform#resid_fields, :waveform) or envelope fields
        # (Envelope#resid_fields, :envelope).
        FIELDS = [
          [:dword, :waveform, 0], [:dword, :waveform, 1], [:word, :envelope, 0], [:word, :envelope, 1],
          [:byte, :envelope, 2], [:byte, :envelope, 3], [:byte, :envelope, 4], [:word, :envelope, 5],
          [:word, :envelope, 6], [:byte, :envelope, 7], [:byte, :waveform, 2], [:dword, :waveform, 3],
          [:dword, :waveform, 4], [:word, :waveform, 5]
        ].freeze

        module_function

        def reads?(section) = section.major == MAJOR && section.minor == MINOR

        # `computer`'s SID must have caught up.
        def export(computer)
          sid = computer.sid
          fields = FieldWriter.new.bytes(Array.new(0x20) { |reg| sid.register(reg) })
          value, ttl = sid.bus_state
          fields.byte(value).dword(ttl)
          voices = sid.voices.map { |voice| [voice.waveform.resid_fields, voice.envelope.resid_fields] }
          FIELDS.each do |width, part, index|
            voices.each { |waveform, envelope| write(fields, width, (part == :waveform ? waveform : envelope)[index]) }
          end
          fields.byte(0).byte(0).byte(VOICE_MASK).section(NAME, MAJOR, MINOR)
        end

        def write(fields, width, value)
          case width
          when :byte then fields.byte(value)
          when :word then fields.word(value)
          else fields.dword(value)
          end
        end

        def import(section, computer)
          sid = computer.sid
          voices = sid.voices
          fields = FieldReader.new(section).skip(0x20)
          sid.restore_bus(fields.byte, fields.dword)
          waveforms = Array.new(voices.length * WAVEFORM_FIELDS, 0)
          envelopes = Array.new(voices.length * ENVELOPE_FIELDS, 0)
          FIELDS.each do |width, part, index|
            voices.length.times do |n|
              if part == :waveform
                waveforms[(n * WAVEFORM_FIELDS) + index] = value(fields, width)
              else
                envelopes[(n * ENVELOPE_FIELDS) + index] = value(fields, width)
              end
            end
          end
          voices.each_with_index do |voice, n|
            voice.waveform.restore_resid_fields(waveforms, n * WAVEFORM_FIELDS)
            voice.envelope.restore_resid_fields(envelopes, n * ENVELOPE_FIELDS)
          end
        end

        def value(fields, width)
          case width
          when :byte then fields.byte
          when :word then fields.word
          else fields.dword
          end
        end
      end
    end
  end
end
