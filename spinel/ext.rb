# frozen_string_literal: true

require "fileutils"
require "rbconfig"

# Compiles a Spinel harness's kernel into a CRuby extension, so CRuby can
# call it in process instead of running a binary and parsing what it
# prints. Backs `rake spinel:lorenz` with EXT=1.
module SpinelExt
  DIR = "tmp/spinel/ext"
  # The flags spinel compiles a binary with.
  CFLAGS = %w[-O2 -fPIC -Wno-all -ffunction-sections -fdata-sections -ffp-contract=off
              -falign-functions=64 -falign-loops=64].freeze

  module_function

  # Compiles spinel/<kernel>.rb with `spinel --ext cruby` into a CRuby
  # extension at path(name), exporting entries (as "Mod.method"). The
  # runtime comes from the Spinel installation's lib/ as sources, since its
  # archive isn't position independent, and the C flags are the ones a
  # Spinel binary gets. The extension binds its own symbols first: the
  # runtime's re_exec would otherwise resolve to glibc's.
  def build(spinel, name, kernel, entries, cc: nil)
    FileUtils.mkdir_p(DIR)
    source = File.join(DIR, "#{name}.c")
    args = [spinel, "-I", "lib", "--no-line-map", "--rbs", "spinel/sig", "spinel/#{kernel}.rb", "-c",
            "--ext", "cruby", "--ext-init", "spx_init_#{name}", "--ext-entry", entries.join(","), "-o", source]
    puts args.join(" ")
    system(*args) || raise("Spinel failed to compile spinel/#{kernel}.rb as an extension")

    runtime = spinel_runtime(spinel)
    command = [*(cc || "cc").split, *CFLAGS, *link_flags,
               "-I#{RbConfig::CONFIG['rubyhdrdir']}", "-I#{RbConfig::CONFIG['rubyarchhdrdir']}",
               "-I#{DIR}", "-I#{runtime}", "-I#{runtime}/regexp", "-I#{runtime}/regexp/shim",
               source, File.join(DIR, "#{name}_ext.c"),
               *Dir.glob("#{runtime}/*.c"), *Dir.glob("#{runtime}/regexp/*.c"), "-lm", "-o", path(name)]
    puts "#{command.first(12).join(' ')} ..."
    system(*command) || raise("The C compiler failed to build #{path(name)}")
  end

  def link_flags
    if RbConfig::CONFIG["host_os"].include?("darwin")
      %w[-bundle -Wl,-undefined,dynamic_lookup]
    else
      %w[-shared -Wl,-Bsymbolic]
    end
  end

  # The runtime sources of the Spinel installation spinel belongs to:
  # bin/spinel beside lib/.
  def spinel_runtime(spinel)
    compiler = find_executable(spinel)
    raise "Can't find #{spinel} to locate its runtime" unless compiler

    runtime = File.expand_path("../lib", File.dirname(File.realpath(compiler)))
    raise "No Spinel runtime sources in #{runtime}" unless File.exist?(File.join(runtime, "spinel_rt.h"))

    runtime
  end

  def find_executable(command)
    return command if command.include?("/")

    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
       .map { |dir| File.join(dir, command) }
       .find { |candidate| File.executable?(candidate) }
  end

  def path(name)
    "#{DIR}/#{name}.#{RbConfig::CONFIG['DLEXT']}"
  end
end
