# frozen_string_literal: true

require "spec_helper"
require "badline/gui"

describe Badline::GUI::Window do
  subject(:window) { described_class.new(title: "Badline", width: 384, height: 272) }

  let(:sdl) { Badline::SDL }
  let(:handle) { Fiddle::Pointer.new(0x1000) }
  let(:renderer) { Fiddle::Pointer.new(0x2000) }

  before do
    allow(sdl).to receive_messages(SDL_InitSubSystem: 0, SDL_SetHint: 1, SDL_CreateWindow: handle,
                                   SDL_CreateRenderer: renderer, SDL_RenderSetLogicalSize: 0)
    %i[SDL_SetWindowTitle SDL_SetRenderDrawColor SDL_RenderClear SDL_RenderPresent
       SDL_DestroyRenderer SDL_DestroyWindow SDL_QuitSubSystem].each do |function|
      allow(sdl).to receive(function)
    end
  end

  it "opens at twice the screen's size" do
    window
    expect(sdl).to have_received(:SDL_CreateWindow)
      .with("Badline", sdl::WINDOWPOS_CENTERED, sdl::WINDOWPOS_CENTERED, 768, 544, sdl::WINDOW_RESIZABLE)
  end

  it "syncs to the display by default" do
    window
    expect(sdl).to have_received(:SDL_CreateRenderer)
      .with(handle, -1, sdl::RENDERER_ACCELERATED | sdl::RENDERER_PRESENTVSYNC)
  end

  it "leaves the sync off when asked" do
    described_class.new(title: "Badline", width: 384, height: 272, vsync: false)
    expect(sdl).to have_received(:SDL_CreateRenderer).with(handle, -1, sdl::RENDERER_ACCELERATED)
  end

  it "raises SDL's reason when no renderer fits" do
    allow(sdl).to receive_messages(SDL_CreateRenderer: nil, SDL_GetError: "Couldn't find matching render driver")
    expect { window }.to raise_error(Badline::GUI::SDLError, /render driver/)
  end

  it "sets the title" do
    window.title = "Badline [JOY]"
    expect(sdl).to have_received(:SDL_SetWindowTitle).with(handle, "Badline [JOY]")
  end

  it "renders each pane between the clear and the present" do
    pane = instance_double(Badline::GUI::ScreenPane, render: nil)
    window.draw([pane])
    expect(pane).to have_received(:render).with(renderer)
  end

  it "presents the frame" do
    window.draw([])
    expect(sdl).to have_received(:SDL_RenderPresent).with(renderer)
  end

  describe "#refresh_rate" do
    # SDL_DisplayMode: Uint32 format; int w, h, refresh_rate.
    def display_mode(rate) = ->(_, mode) { (mode[0, 16] = [0, 1920, 1080, rate].pack("L l3")) && 0 }

    it "reads the display's" do
      allow(sdl).to receive(:SDL_GetCurrentDisplayMode, &display_mode(50))
      expect(window.refresh_rate).to eq(50)
    end

    it "falls back when the display doesn't say" do
      allow(sdl).to receive(:SDL_GetCurrentDisplayMode, &display_mode(0))
      expect(window.refresh_rate).to eq(described_class::DEFAULT_REFRESH_RATE)
    end

    it "falls back when SDL can't tell" do
      allow(sdl).to receive(:SDL_GetCurrentDisplayMode).and_return(-1)
      expect(window.refresh_rate).to eq(described_class::DEFAULT_REFRESH_RATE)
    end
  end

  it "closes only once" do
    window.close
    window.close
    expect(sdl).to have_received(:SDL_DestroyWindow).once
  end
end
