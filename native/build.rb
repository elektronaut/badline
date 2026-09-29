# frozen_string_literal: true

require "fileutils"
require "open3"

# Builds the native badline with Spinel. Backs `rake native:build`.
module NativeBuild
  OUT = "tmp/native"
  BINARY = "#{OUT}/badline".freeze
  # Where the build writes its own badline/native/build_info.rb, ahead of
  # the one in native/lib on the load path.
  GENERATED = "#{OUT}/lib".freeze
  # Where SDL2 lives when neither pkg-config nor sdl2-config can say.
  FALLBACK_LIB_DIRS = %w[/opt/homebrew/lib /usr/local/lib].freeze

  module_function

  # `cc` is the C compiler command (default `cc`), and `sdl2_flags` the
  # flags that find libSDL2 (default: what pkg-config or sdl2-config says).
  def build(spinel, cc: nil, sdl2_flags: nil, out: BINARY)
    FileUtils.mkdir_p(File.dirname(out))
    write_build_info(spinel)
    args = command(spinel, cc: cc || "cc", sdl2_flags: sdl2_flags || self.sdl2_flags, out:)
    puts args.join(" ")
    system(*args) || raise("Spinel failed to build native/badline.rb")
  end

  def command(spinel, cc:, sdl2_flags:, out:)
    [spinel, "-I", GENERATED, "-I", "native/lib", "-I", "lib", "--no-line-map", "--rbs", "spinel/sig",
     "native/badline.rb", "-o", out, "--cc=#{[cc, sdl2_flags].reject(&:empty?).join(' ')}"]
  end

  # The linker flags that find libSDL2: the -L directories pkg-config, or
  # failing that sdl2-config, gives. The libraries themselves come from
  # the FFI declarations.
  def sdl2_flags
    output = capture("pkg-config", "--libs", "sdl2") || capture("sdl2-config", "--libs")
    return lib_dirs(output) if output

    FALLBACK_LIB_DIRS.select { |dir| Dir.exist?(dir) }.map { |dir| "-L#{dir}" }.join(" ")
  end

  def lib_dirs(libs)
    libs.split.select { |flag| flag.start_with?("-L") }.join(" ")
  end

  def write_build_info(spinel)
    path = File.join(GENERATED, "badline/native/build_info.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, build_info(revision: revision, spinel: spinel_version(spinel)))
  end

  def build_info(revision:, spinel:)
    <<~RUBY
      # frozen_string_literal: true

      # Written by rake native:build.
      module Badline
        module Native
          REVISION = #{revision.dump}
          SPINEL = #{spinel.dump}
        end
      end
    RUBY
  end

  def revision
    capture("git", "describe", "--tags", "--always", "--dirty", "--abbrev=8") || ""
  end

  def spinel_version(spinel)
    version = capture(spinel, "--version") || ""
    version.start_with?("spinel ") ? version : ""
  end

  def capture(*command)
    out, status = Open3.capture2(*command, err: File::NULL)
    out.strip if status.success?
  rescue SystemCallError
    nil
  end
end
