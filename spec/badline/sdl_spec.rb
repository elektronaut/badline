# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/sdl"

# The binding both builds use, run on CRuby against SDL's dummy drivers.
describe Badline::SDL do
  around do |example|
    drivers = %w[SDL_VIDEODRIVER SDL_AUDIODRIVER SDL_RENDER_DRIVER].to_h { |name| [name, ENV.fetch(name, nil)] }
    ENV.update("SDL_VIDEODRIVER" => "dummy", "SDL_AUDIODRIVER" => "dummy", "SDL_RENDER_DRIVER" => "software")
    example.run
  ensure
    ENV.update(drivers)
  end

  describe "the events" do
    def drain
      nil while described_class.SDL_PollEvent(described_class.event) == 1
    end

    # Each example starts from an empty queue, whatever another spec's
    # subsystems left in it, such as the audio's device events.
    before do
      described_class.SDL_InitSubSystem(described_class::INIT_EVENTS)
      drain
    end

    after do
      drain
      described_class.SDL_QuitSubSystem(described_class::INIT_EVENTS)
    end

    # A key going down: type, timestamp, window id, state, repeat, two bytes
    # of padding, then the keysym: scancode, sym, mod.
    def push_key
      event = [0x300, 0, 1, 1, 1, 0, 0, 43, described_class::KEY_TAB, described_class::KMOD_SHIFT]
      described_class.SDL_PushEvent(event.pack("L3C4l2S").ljust(56, "\0"))
    end

    def fields(event)
      %i[event_type event_scancode event_sym event_mod event_repeat].map { |field| described_class.send(field, event) }
    end

    it "queues nothing until something happens" do
      expect(described_class.SDL_PollEvent(described_class.event)).to eq(0)
    end

    it "reads the event pushed" do
      push_key
      described_class.SDL_PollEvent(described_class.event)
      expect(fields(described_class.event))
        .to eq([described_class::KEYDOWN, 43, described_class::KEY_TAB, described_class::KMOD_SHIFT, 1])
    end

    # A drop event's file, which SDL leaves to the receiver to free, put
    # where SDL_PollEvent leaves it. The queue can't carry one pushed by
    # hand: sdl2-compat drops the path on the way through.
    def dropped(path)
      file = Badline::LibC.malloc(path.bytesize + 1)
      file[0, path.bytesize + 1] = "#{path}\0"
      described_class.event[8, 8] = [file.to_i].pack("J")
    end

    it "reads the path of the file dropped" do
      dropped("game.d64")
      expect(described_class.dropped_file).to eq("game.d64")
    end
  end

  describe "the window" do
    let(:window) { described_class.SDL_CreateWindow("Badline", 0, 0, 384, 272, 0) }
    let(:renderer) { described_class.SDL_CreateRenderer(window, -1, 0) }

    before { described_class.SDL_Init(described_class::INIT_VIDEO | described_class::INIT_EVENTS) }

    after { described_class.SDL_Quit }

    def output_size
      described_class.SDL_GetRendererOutputSize(renderer, described_class.output_w, described_class.output_h)
      [described_class.read_i32(described_class.output_w), described_class.read_i32(described_class.output_h)]
    end

    def fill(red, green, blue)
      rect = described_class.led_rect
      [[:rect_x, 2], [:rect_y, 3], [:rect_w, 1], [:rect_h, 1]].each do |field, value|
        described_class.send(field, rect, value)
      end
      described_class.SDL_SetRenderDrawColor(renderer, red, green, blue, 0xff)
      described_class.SDL_RenderFillRect(renderer, rect)
    end

    def read_pixel
      pixel = IO::Buffer.new(4)
      described_class.SDL_RenderReadPixels(renderer, described_class.led_rect,
                                           described_class::PIXELFORMAT_RGB888, pixel, 4)
      pixel.get_value(:u32, 0) & 0xffffff
    end

    it "opens a window and a renderer" do
      expect([window, renderer]).to all(be_a(Fiddle::Pointer))
    end

    it "sizes the renderer's output as the window" do
      expect(output_size).to eq([384, 272])
    end

    it "reads back what it drew" do
      fill(0x12, 0x34, 0x56)
      expect(read_pixel).to eq(0x123456)
    end
  end

  describe "the audio queue" do
    subject(:device) do
      described_class.spec_freq(described_class.wanted, 8000)
      described_class.spec_format(described_class.wanted, described_class::AUDIO_S16LSB)
      described_class.spec_channels(described_class.wanted, 1)
      described_class.spec_samples(described_class.wanted, 512)
      described_class.SDL_OpenAudioDevice(nil, 0, described_class.wanted, described_class.obtained, 0)
    end

    before { described_class.SDL_InitSubSystem(described_class::INIT_AUDIO) }

    after do
      described_class.SDL_CloseAudioDevice(device)
      described_class.SDL_QuitSubSystem(described_class::INIT_AUDIO)
    end

    it "opens at the rate asked for" do
      device
      expect(described_class.read_i32(described_class.obtained)).to eq(8000)
    end

    it "queues the samples of an IO::Buffer" do
      described_class.SDL_QueueAudio(device, IO::Buffer.new(800), 800)
      expect(described_class.SDL_GetQueuedAudioSize(device)).to be_within(40).of(800)
    end
  end

  it "names a key the way SDL does" do
    expect(described_class.SDL_GetKeyName(described_class::KEY_F10)).to eq("F10")
  end
end
