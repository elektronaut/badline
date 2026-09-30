# frozen_string_literal: true

# Runs the examples against SDL's dummy video and audio drivers and its
# software renderer, in a scratch working directory.
RSpec.shared_context "with SDL's dummy drivers" do
  around do |example|
    drivers = %w[SDL_VIDEODRIVER SDL_AUDIODRIVER SDL_RENDER_DRIVER].to_h { |name| [name, ENV.fetch(name, nil)] }
    ENV.update("SDL_VIDEODRIVER" => "dummy", "SDL_AUDIODRIVER" => "dummy", "SDL_RENDER_DRIVER" => "software")
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  ensure
    ENV.update(drivers)
  end
end
