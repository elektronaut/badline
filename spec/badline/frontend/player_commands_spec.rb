# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::PlayerCommands do
  subject(:commands) { described_class.new(state) }

  let(:state) { Badline::Frontend::PlayerState.new }

  it "passes the jukebox's actions on" do
    expect(%i[next pause seek forward all_subtunes].map { |action| commands.handle(action) })
      .to eq(%i[next pause seek forward all_subtunes])
  end

  it "keeps the view and the model to itself" do
    expect(%i[view sid chip mos8580].map { |action| commands.handle(action) }).to all(be_nil)
  end

  it "steps through the views and wraps around" do
    3.times { commands.handle(:view) }
    expect(state.view).to eq(0)
  end

  it "shows the view clicked" do
    commands.handle(:sid)
    expect(state.view).to eq(1)
  end

  it "steps through the models and wraps around" do
    chips = Array.new(3) do
      commands.handle(:chip)
      state.chip
    end
    expect(chips).to eq([1, 2, 0])
  end

  it "picks the model clicked" do
    commands.handle(:mos8580)
    expect(state.chip).to eq(2)
  end

  it "keeps the SID shown to itself" do
    expect(commands.handle(:sid2)).to be_nil
  end

  it "shows the SID clicked" do
    commands.handle(:sid3)
    expect(state.sid).to eq(2)
  end
end
