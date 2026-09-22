# frozen_string_literal: true

require "badline/sid/waveform"
require "badline/sid/envelope"
require "badline/sid/voice"
require "badline/sid/filter"

module Badline
  # SID (Sound Interface Device) chip, in either the 6581 or the 8580
  # revision.
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
  # read out the mixed result. The DSP is clocked lazily and catches up when
  # something asks for its state.
  #
  # The 6581 drives its voices well above ground, so the mix carries a large
  # DC offset that the RC network on the C64 board filters out.
  class SID
    include Addressable

    VOICES = 3

    # Cycles the data bus holds a value, measured through SID/bitfade.
    BUS_TTL = { mos6581: 0x1d00, mos8580: 0xa2000 }.freeze

    # Scales the filter's 20-bit mix down to a signed 16-bit sample.
    SAMPLE_DIVISOR = ((0xfff * 0xff) >> 7) * 3 * 15 * 2 / (2**16)

    # Writes the idle DSP remembers in full. Past that the oldest one is
    # applied where the replay stands and its timing is lost.
    DEFERRED_WRITES = 0x400

    attr_accessor :pots
    attr_reader :model, :voices, :filter

    def initialize(model: :mos6581, pots: nil)
      addressable_at(0xd400, length: 2**10)
      @model = model
      @registers = Memory.new(length: 2**5)
      @pots = pots
      @bus_value = 0x00
      @bus_ttl = 0
      @bus_ttl_reset = BUS_TTL.fetch(model)
      @voices = Array.new(VOICES) { Voice.new(model:) }
      @voice1, @voice2, @voice3 = @voices
      @waveform1, @waveform2, @waveform3 = @voices.map(&:waveform)
      @filter = Filter.new(model:)
      @synthesizing = false
      @idle_cycles = 0
      @deferred_writes = []
      link_oscillators
    end

    # Clocking three oscillators, three envelopes and the filter cuts
    # emulation speed by about 40%, so the DSP idles until something asks
    # for its state, then replays the cycles it skipped.
    def synthesizing? = @synthesizing

    def synthesize!
      return if @synthesizing

      @synthesizing = true
      catch_up
    end

    # Voice 3's oscillator and envelope, the only synthesis state the CPU
    # can see. Programs poll OSC3 with the noise waveform selected for
    # random numbers, and ENV3 to time hard restarts.
    def osc3
      synthesize!
      @voices[2].waveform.osc3 >> 4
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
      @synthesizing ? clock! : @idle_cycles += 1
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

    # Unrolled over the three voices: the per-cycle block calls cost
    # measurably on the synthesis path.
    def clock!
      @voice1.cycle!
      @voice2.cycle!
      @voice3.cycle!
      @waveform1.synchronize!
      @waveform2.synchronize!
      @waveform3.synchronize!
      @filter.cycle!(@voices)
    end

    # Runs the cycles the DSP sat out, landing each deferred write on the
    # cycle the CPU wrote it on.
    def catch_up
      replayed = 0
      @deferred_writes.each do |cycle, reg, value|
        (cycle - replayed).times { clock! }
        replayed = cycle
        apply_write(reg, value)
      end
      (@idle_cycles - replayed).times { clock! }
      @deferred_writes.clear
      @idle_cycles = 0
    end

    def latch(value)
      @bus_ttl = @bus_ttl_reset
      @bus_value = value
    end

    def age_bus
      @bus_ttl -= 1
      @bus_value = 0x00 if @bus_ttl.zero?
    end

    def write_register(reg, value)
      @registers.poke(reg, value)
      @synthesizing ? apply_write(reg, value) : defer_write(reg, value)
    end

    def defer_write(reg, value)
      apply_write(*@deferred_writes.shift.last(2)) if @deferred_writes.length == DEFERRED_WRITES
      @deferred_writes << [@idle_cycles, reg, value]
    end

    def apply_write(reg, value)
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
