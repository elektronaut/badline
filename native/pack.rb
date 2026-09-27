# frozen_string_literal: true

require "fileutils"
require_relative "build"
require_relative "../lib/badline/version"

# Packs the native badline into a tarball that builds with a C compiler and
# make alone, from Spinel's `spin pack`. Backs `rake native:pack`.
module NativePack
  OUT = "#{NativeBuild::OUT}/pack".freeze
  # The spin project `spin pack` runs in: the entry point, the type
  # signatures and a manifest naming the load path as path dependencies.
  PROJECT = "#{OUT}/project".freeze
  # The pack's own build_info.rb, ahead of native/lib on the load path.
  GENERATED = "#{OUT}/lib".freeze

  module_function

  # `spinel` is the compiler, and `spin` the spin beside it unless named.
  def pack(spinel, spin: nil)
    spinel_line = spinel_release(NativeBuild.spinel_version(spinel))
    raise "#{spinel} --version doesn't name a Spinel build" if spinel_line.empty?

    info = { version: Badline::VERSION, revision: NativeBuild.revision, spinel: spinel_line }
    tree = File.join(OUT, directory_name(info[:version]))
    stage(info)
    run_pack(spin || File.join(File.dirname(spinel), "spin"), tree)
    add_files(tree, info)
    archive(tree, tarball(info))
  end

  def stage(info)
    FileUtils.rm_rf([PROJECT, GENERATED])
    FileUtils.mkdir_p(["#{PROJECT}/bin", "#{PROJECT}/sig", "#{GENERATED}/badline/native"])
    FileUtils.cp("native/badline.rb", "#{PROJECT}/bin/badline.rb")
    FileUtils.cp(Dir.glob("spinel/sig/*.rbs"), "#{PROJECT}/sig")
    File.write("#{GENERATED}/badline/native/build_info.rb",
               NativeBuild.build_info(revision: info[:revision], spinel: info[:spinel]))
    File.write("#{PROJECT}/spin.toml", spin_toml([GENERATED, "native/lib", "lib"].map { |dir| File.expand_path(dir) }))
  end

  # spin puts the dependencies on the load path in the order they're listed.
  def spin_toml(load_path)
    deps = load_path.each_with_index.map { |dir, i| "load_path_#{i} = { path = #{dir.dump} }" }
    "[package]\nname = \"badline\"\n\n[dependencies]\n#{deps.join("\n")}\n"
  end

  def run_pack(spin, tree)
    FileUtils.rm_rf(tree)
    system(File.expand_path(spin), "pack", "badline", "--out", File.expand_path(tree), chdir: PROJECT) ||
      raise("spin pack failed")
  end

  def add_files(tree, info)
    FileUtils.cp_r("lib/badline/roms", tree)
    FileUtils.cp(["MIT-LICENSE", "native/README.md"], tree)
    File.write(File.join(tree, "PACK-INFO"), manifest(info))
  end

  def archive(tree, path)
    system("tar", "-czf", File.expand_path(path), "-C", File.dirname(tree), File.basename(tree)) ||
      raise("tar failed")
    puts "Packed #{path}"
    path
  end

  def directory_name(version)
    "badline-#{version}"
  end

  def tarball(info)
    File.join(NativeBuild::OUT, "#{directory_name(info[:version])}-spinel-#{spinel_commit(info[:spinel])}.tar.gz")
  end

  def manifest(info)
    <<~TEXT
      badline #{info[:version]}
      revision #{info[:revision]}
      #{info[:spinel]}
    TEXT
  end

  # The compiler's version without the C compiler it was built with, which
  # isn't the one that compiles the pack.
  def spinel_release(version)
    version.sub(/\s*\[[^\]]*\]\z/, "")
  end

  def spinel_commit(version)
    version[/\(([0-9a-f]+)\)/, 1] || "unknown"
  end
end
