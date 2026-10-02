# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::PlayerState do
  subject(:state) { described_class.new }

  def play(*seconds) = seconds.each { |second| state.elapsed = second }

  it "seeks until playback comes up to the target" do
    state.seek(40.0)
    play(10.0, 20.0)
    expect(state).to be_seeking
  end

  it "stops seeking once playback reaches the target" do
    state.seek(40.0)
    play(10.0, 40.5)
    expect(state).not_to be_seeking
  end

  it "keeps seeking back while playback is still past the target" do
    state.seek(20.0)
    play(50.0)
    expect(state).to be_seeking
  end

  it "stops seeking back once playback restarts and reaches the target" do
    state.seek(20.0)
    play(50.0, 0.5, 20.0)
    expect(state).not_to be_seeking
  end
end
