# frozen_string_literal: true

require_relative "lib/badline/version"

Gem::Specification.new do |spec|
  spec.name = "badline"
  spec.version = Badline::VERSION
  spec.authors = ["Inge Jørgensen"]
  spec.email = ["inge@elektronaut.no"]

  spec.summary = "A cycle-accurate Commodore 64 emulator"
  spec.description = "Badline is a Commodore 64 emulator written in Ruby, " \
                     "implementing cycle-accurate timing and hardware behavior. " \
                     "Supports PRG/P00 programs, D64/D71/D81 disk images and " \
                     "CRT cartridges."
  spec.homepage = "https://github.com/elektronaut/badline"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?("bin/", "test/", "spec/", ".git", ".rubocop",
                      ".release-please", "release-please", "Gemfile", "Rakefile")
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ruby-sdl2", "~> 0.3"
end
