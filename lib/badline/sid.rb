# frozen_string_literal: true

require "badline/sid/waveform"
require "badline/sid/envelope"
require "badline/sid/voice"
require "badline/sid/filter"

module Badline
  # SID (Sound Interface Device) chip, 6581 revision.
  #
  # $D400-$D418 - Voices, filter and volume   - write only
  # $D419-$D41A - POTX/POTY paddle inputs     - read only
  # $D41B-$D41C - Voice 3 oscillator/envelope - read only
  # $D41D-$D41F - Unconnected
  #
  # The register file mirrors every 32 bytes up to $D7FF.
  #
  # Reading a write-only or unconnected register returns the last byte the
  # SID saw on the data bus. That value fades to $00 as the capacitance
  # holding it drains. Paddles and the 1351 mouse attach as a pots source
  # responding to #pot_x and #pot_y; with none attached the lines read $FF.
  #
  # Three voices feed the filter and the master volume; #output and #sample
  # read out the mixed result. The DSP is clocked lazily, so until something
  # reads OSC3/ENV3 or pulls a sample the voices hold their power-on state.
  #
  # The 6581 drives its voices well above ground, so the mix carries a large
  # DC offset that the RC network on the C64 board filters out.
  class SID
    include Addressable

    VOICES = 3

    # Cycles the data bus holds a value on the 6581, measured through
    # SID/bitfade (the 8580 holds it for roughly $a2000).
    BUS_TTL = 0x1d00

    # Scales the filter's 20-bit mix down to a signed 16-bit sample.
    SAMPLE_DIVISOR = ((0xfff * 0xff) >> 7) * 3 * 15 * 2 / (2**16)

    attr_accessor :pots
    attr_reader :voices, :filter

    def initialize(pots: nil)
      addressable_at(0xd400, length: 2**10)
      @registers = Memory.new(length: 2**5)
      @pots = pots
      @bus_value = 0x00
      @bus_ttl = 0
      @voices = Array.new(VOICES) { Voice.new }
      @filter = Filter.new
      @synthesizing = false
      link_oscillators
    end

    # Clocking three oscillators, three envelopes and the filter cuts
    # emulation speed by about 40%, so the DSP idles until something asks
    # for its state.
    def synthesizing? = @synthesizing

    def synthesize!
      @synthesizing = true
    end

    # Voice 3's oscillator and envelope, the only synthesis state the CPU
    # can see. Programs poll OSC3 with the noise waveform selected for
    # random numbers, and ENV3 to time hard restarts.
    def osc3
      synthesize!
      @voices[2].waveform.output >> 4
    end

    def env3
      synthesize!
      @voices[2].envelope.output
    end

    def output
      synthesize!
      @filter.output
    end

    def sample = (output / SAMPLE_DIVISOR).clamp(-0x8000, 0x7fff)

    def cycle!
      age_bus if @bus_ttl.positive?
      return unless @synthesizing

      @voices.each(&:cycle!)
      @voices.each { |voice| voice.waveform.synchronize! }
      @filter.cycle!(@voices)
    end

    def peek(addr)
      case index(addr) % (2**5)
      when 0x19 then latch(pots ? pots.pot_x : 0xff)
      when 0x1a then latch(pots ? pots.pot_y : 0xff)
      when 0x1b then latch(osc3)
      when 0x1c then latch(env3)
      else @bus_value
      end
    end

    def poke(addr, value)
      reg = index(addr) % (2**5)
      write_register(reg, value) if reg <= 0x18
      latch(value)
    end

    # Register contents as written, for save states and debugging.
    def register(reg) = @registers.peek(reg)

    private

    # Each voice hard-syncs and ring-modulates against the previous one,
    # wrapping from voice 1 back round to voice 3.
    def link_oscillators
      waveforms = @voices.map(&:waveform)
      waveforms.each_with_index do |waveform, i|
        waveform.sync_source = waveforms[i - 1]
        waveform.sync_dest = waveforms[(i + 1) % VOICES]
      end
    end

    def latch(value)
      @bus_ttl = BUS_TTL
      @bus_value = value
    end

    def age_bus
      @bus_ttl -= 1
      @bus_value = 0x00 if @bus_ttl.zero?
    end

    def write_register(reg, value)
      @registers.poke(reg, value)
      reg < 0x15 ? write_voice(reg, value) : @filter.write(reg, value)
    end

    def write_voice(reg, value)
      voice = @voices[reg / 7]
      case reg % 7
      when 0 then voice.waveform.frequency_low = value
      when 1 then voice.waveform.frequency_high = value
      when 2 then voice.waveform.pulse_width_low = value
      when 3 then voice.waveform.pulse_width_high = value
      when 4 then voice.control = value
      when 5 then voice.envelope.attack_decay = value
      when 6 then voice.envelope.sustain_release = value
      end
    end
  end
end
