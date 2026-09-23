# frozen_string_literal: true

require "badline/sid/waveform"
require "badline/sid/envelope"
require "badline/sid/voice"
require "badline/sid/filter"
require "badline/sid/decimator"

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
  # read out the mixed result, and #record collects it at an audio rate for
  # #drain_samples. The DSP is clocked lazily and catches up when something
  # asks for its state.
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

    # Writes the DSP queues between catch-ups. A full queue catches up
    # there and then, so no write loses its timing.
    DEFERRED_WRITES = 0x400

    # Cycles the filter integrates in one step while synthesizing, after
    # reSID's delta_t_flt. 1 makes the audio exact, at a per-cycle cost.
    FILTER_CHUNK = 4

    attr_accessor :pots
    attr_reader :model

    def initialize(model: :mos6581, pots: nil, filter_chunk: FILTER_CHUNK)
      addressable_at(0xd400, length: 2**10)
      @model = model
      @pots = pots
      @bus_ttl_reset = BUS_TTL.fetch(model)
      @filter = Filter.new(model:)
      @synthesizing = false
      @pending_cycles = 0
      @deferred_writes = []
      @decimator = nil
      @samples = []
      @filter_chunk = filter_chunk
      @voices = Voice.linked(VOICES, model:)
      @voice1, @voice2, @voice3 = @voices
      @waveform1, @waveform2, @waveform3 = @voices.map(&:waveform)
      reset!
    end

    # The RES line clears the registers, the data bus, the filter and the
    # voices, all but their accumulators. Recording carries on across it.
    def reset!
      catch_up
      @registers = Memory.new(length: 2**5)
      @bus_value = 0x00
      @bus_ttl = 0
      @voices.each(&:reset!)
      @filter.reset
    end

    # The DSP only counts cycles as they pass. Whatever asks for its state
    # catches it up, a span at a time: each span fast-forwards the voices
    # and ends on one whole cycle, so everything the CPU can read stays
    # exact. The filter only runs once something wants audio.
    def synthesizing? = @synthesizing

    def synthesize!
      return if @synthesizing

      @synthesizing = true
      catch_up
    end

    # Starts collecting the output, averaged down to `rate` samples a
    # second, for #drain_samples. `filter_chunk` overrides the one the SID
    # was built with, for a machine that built its own. `clock_hz` is the
    # rate the SID's cycles are taken to run at.
    def record(rate:, filter_chunk: @filter_chunk, clock_hz: TimeOfDay::CLOCK_HZ)
      synthesize!
      catch_up
      @filter_chunk = filter_chunk
      @decimator = Decimator.new(clock_hz:, rate:)
      @samples = []
    end

    # The samples recorded since the last drain.
    def drain_samples
      catch_up
      samples = @samples
      @samples = []
      samples
    end

    def voices
      catch_up
      @voices
    end

    def filter
      catch_up
      @filter
    end

    # Voice 3's oscillator and envelope, the only synthesis state the CPU
    # can see. Programs poll OSC3 with the noise waveform selected for
    # random numbers, and ENV3 to time hard restarts.
    def osc3
      catch_up
      @waveform3.osc3 >> 4
    end

    def env3
      catch_up
      @voice3.envelope.env3
    end

    def output
      synthesize!
      catch_up
      @filter.output
    end

    def sample
      output
      current_sample
    end

    def cycle!
      age_bus if @bus_ttl != 0
      @pending_cycles += 1
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

    # Runs the cycles that have passed, landing each queued write on the
    # cycle the CPU wrote it on.
    def catch_up
      replayed = 0
      @deferred_writes.each do |cycle, reg, value|
        run(cycle - replayed)
        replayed = cycle
        apply_write(reg, value)
      end
      run(@pending_cycles - replayed)
      @deferred_writes.clear
      @pending_cycles = 0
    end

    def run(cycles)
      while cycles.positive?
        span = span(cycles)
        fast_forward(span - 1) if span > 1
        clock!(span)
        cycles -= span
      end
    end

    # The longest stretch that can be fast-forwarded. A combined waveform
    # feeding back into its own oscillator steps cycle by cycle, and a span
    # never runs past an MSB rise that hard-syncs the next voice, so both
    # land on a whole cycle.
    def span(cycles)
      synthesizing = @synthesizing
      return 1 if @waveform1.stepped?(synthesizing) || @waveform2.stepped?(synthesizing) ||
                  @waveform3.stepped?(synthesizing)

      span = synthesizing ? synthesis_span(cycles) : cycles
      span = sync_span(@waveform1, span)
      span = sync_span(@waveform2, span)
      sync_span(@waveform3, span)
    end

    # The filter steps at most @filter_chunk cycles at a time, and never
    # across the end of a recorded sample.
    def synthesis_span(cycles)
      span = [cycles, @filter_chunk].min
      return span unless @decimator

      [@decimator.cycles_to_close, span].min
    end

    def sync_span(waveform, span)
      return span unless waveform.sync_dest.sync?

      rise = waveform.cycles_to_msb_rise
      rise && rise < span ? rise : span
    end

    # Unrolled over the three voices: the per-cycle block calls cost
    # measurably on the synthesis path.
    def fast_forward(cycles)
      @voice1.fast_forward(cycles)
      @voice2.fast_forward(cycles)
      @voice3.fast_forward(cycles)
    end

    # The last cycle of a span, run whole. The filter integrates the span
    # from the voices' output at its end.
    def clock!(span)
      @voice1.cycle!
      @voice2.cycle!
      @voice3.cycle!
      @waveform1.synchronize!
      @waveform2.synchronize!
      @waveform3.synchronize!
      return unless @synthesizing

      @filter.cycle!(@voices, span)
      record_sample(span) if @decimator
    end

    def record_sample(span)
      sample = @decimator.push(current_sample, span)
      @samples << sample if sample
    end

    def current_sample = (@filter.output / SAMPLE_DIVISOR).clamp(-0x8000, 0x7fff)

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
      catch_up if @deferred_writes.length == DEFERRED_WRITES
      @deferred_writes << [@pending_cycles, reg, value]
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
