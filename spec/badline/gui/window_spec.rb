# frozen_string_literal: true

require "spec_helper"
require "badline/gui"

describe Badline::GUI::Window do
  subject(:window) { described_class.new(title: "Badline", width: 384, height: 272) }

  let(:sdl) { Badline::SDL }
  let(:handle) { Fiddle::Pointer.new(0x1000) }
  let(:renderer) { Fiddle::Pointer.new(0x2000) }

  before do
    allow(sdl::InitSubSystem).to receive(:call).and_return(0)
    allow(sdl::SetHint).to receive(:call).and_return(1)
    allow(sdl::CreateWindow).to receive(:call).and_return(handle)
    allow(sdl::CreateRenderer).to receive(:call).and_return(renderer)
    allow(sdl::RenderSetLogicalSize).to receive(:call).and_return(0)
    %i[SetWindowTitle SetRenderDrawColor RenderClear RenderPresent
       DestroyRenderer DestroyWindow QuitSubSystem].each do |function|
      allow(sdl.const_get(function)).to receive(:call)
    end
  end

  it "opens at twice the screen's size" do
    window
    expect(sdl::CreateWindow).to have_received(:call)
      .with("Badline", sdl::WINDOWPOS_CENTERED, sdl::WINDOWPOS_CENTERED, 768, 544, sdl::WINDOW_RESIZABLE)
  end

  it "syncs to the display by default" do
    window
    expect(sdl::CreateRenderer).to have_received(:call)
      .with(handle, -1, sdl::RENDERER_ACCELERATED | sdl::RENDERER_PRESENTVSYNC)
  end

  it "leaves the sync off when asked" do
    described_class.new(title: "Badline", width: 384, height: 272, vsync: false)
    expect(sdl::CreateRenderer).to have_received(:call).with(handle, -1, sdl::RENDERER_ACCELERATED)
  end

  it "raises SDL's reason when no renderer fits" do
    allow(sdl::CreateRenderer).to receive(:call).and_return(Fiddle::Pointer.new(0))
    allow(sdl::GetError).to receive(:call).and_return("Couldn't find matching render driver")
    expect { window }.to raise_error(sdl::Error, /render driver/)
  end

  it "sets the title" do
    window.title = "Badline [JOY]"
    expect(sdl::SetWindowTitle).to have_received(:call).with(handle, "Badline [JOY]")
  end

  it "renders each pane between the clear and the present" do
    pane = instance_double(Badline::GUI::ScreenPane, render: nil)
    window.draw([pane])
    expect(pane).to have_received(:render).with(renderer)
  end

  it "presents the frame" do
    window.draw([])
    expect(sdl::RenderPresent).to have_received(:call).with(renderer)
  end

  describe "#refresh_rate" do
    def display_mode(rate) = [0, 1920, 1080, rate].pack("L l3").ljust(described_class::DISPLAY_MODE_SIZE, "\0")

    it "reads the display's" do
      allow(sdl::GetCurrentDisplayMode).to receive(:call) { |_, mode| mode.replace(display_mode(50)) && 0 }
      expect(window.refresh_rate).to eq(50)
    end

    it "falls back when the display doesn't say" do
      allow(sdl::GetCurrentDisplayMode).to receive(:call) { |_, mode| mode.replace(display_mode(0)) && 0 }
      expect(window.refresh_rate).to eq(described_class::DEFAULT_REFRESH_RATE)
    end

    it "falls back when SDL can't tell" do
      allow(sdl::GetCurrentDisplayMode).to receive(:call).and_return(-1)
      expect(window.refresh_rate).to eq(described_class::DEFAULT_REFRESH_RATE)
    end
  end

  it "closes only once" do
    window.close
    window.close
    expect(sdl::DestroyWindow).to have_received(:call).once
  end
end
