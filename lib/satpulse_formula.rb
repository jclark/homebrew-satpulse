# frozen_string_literal: true

# Shared definition for the satpulse formulae.
#
# Homebrew loads each formula file independently, so satpulse and satpulse-pre
# would otherwise duplicate their whole body. Both `include SatpulseFormula`,
# which contributes the common dependencies, install logic, service, and test;
# each formula file only declares its own desc, homepage, and download spec.
# (homepage stays in the formula files because brew's Homepage audit is
# AST-based and cannot see it here.)
module SatpulseFormula
  def self.included(formula)
    formula.license "MIT"

    # Pin to go@1.25 to match what the satpulse repo builds and tests against
    # (go.mod: go 1.25.0; its CI uses go-version 1.25.x). Plain "go" tracks the
    # newest Homebrew Go, which the project does not test. go@1.26 can't be used
    # (it is only an alias for the latest "go", which brew audit rejects). Bump
    # this when the project moves to a newer Go line that has a real go@ formula.
    formula.depends_on "go@1.25" => :build
    formula.depends_on "pandoc" => :build
    formula.depends_on :macos

    formula.service do
      # find-serial runs in --exec mode and replaces {} with the current
      # /dev/cu.* path before execing satpulsed. Default match is any USB serial
      # callout device; add --vid/--pid here if multiple are present.
      run [opt_bin/"find-serial", "--exec", "--",
           opt_sbin/"satpulsed", "-f", etc/"satpulse.toml", "-d", "{}"]
      keep_alive true
      log_path var/"log/satpulse/launchd.out.log"
      error_log_path var/"log/satpulse/launchd.err.log"
    end

    formula.test do
      assert_match "satpulse", shell_output("#{bin}/satpulsetool --version")
    end
  end

  def install
    # Build the Go binaries. unix-build.sh derives the embedded version from git,
    # so the build dir must be a real clone with .git (it is, via the git
    # download strategy). It builds for the host GOOS/GOARCH.
    system "./unix-build.sh"
    goarch = Hardware::CPU.arm? ? "arm64" : "amd64"
    out = "out/darwin_#{goarch}"
    sbin.install "#{out}/satpulsed"
    bin.install "#{out}/satpulsetool"

    # find-serial is a standalone Darwin C tool with its own Makefile, built
    # separately from the Go binaries (unix-build.sh does not build it).
    system "make", "-C", "macos"
    bin.install "macos/find-serial"

    # GPS message files (referenced by `satpulsetool gps -m ...`) and the config
    # JSON schema, for parity with the deb/rpm. Install under share/"satpulse"
    # (not pkgshare, which is share/<formula-name> -- "satpulse-pre" for that
    # formula -- so both channels share one path).
    (share/"satpulse").install "configs/gpsmsg"
    (share/"satpulse").install "configs/config-schema.json"

    install_man_pages
    install_config
  end

  # unix-build.sh does not generate man pages (only the Makefile does), so the
  # formula generates them with pandoc and applies the same path substitutions
  # the Makefile does, but against the Homebrew prefix.
  def install_man_pages
    man_pages = %w[
      satpulsetool.1 satpulsetool-gps.1 satpulsetool-pack.1 satpulsetool-scan.1
      satpulsetool-sdp.1 satpulsetool-syncsim.1 satpulsetool-convobs.1
      satpulse.toml.5 satpulsed.8
    ]
    man_pages.each do |page|
      title = File.basename(page, ".*")     # e.g. "satpulse.toml" from "satpulse.toml.5"
      section = File.extname(page)[1..]     # e.g. "5"
      system "pandoc", "-s",
             "--metadata=title=#{title}",
             "--metadata=section=#{section}",
             "--metadata=author=James Clark",
             "-t", "man", "-o", page, "docs/man/#{page}.md"
      # opt_prefix (stable) not the versioned keg; share/satpulse not pkgshare.
      case page
      when "satpulsetool-gps.1"
        inreplace page, "/usr/share/satpulse/gpsmsg", "#{opt_prefix}/share/satpulse/gpsmsg"
      when "satpulsed.8"
        inreplace page, "/etc/satpulse.toml", "#{etc}/satpulse.toml"
      end
      send("man#{section}").install page
    end
  end

  # Install configs/satpulse.toml as the default <prefix>/etc/satpulse.toml.
  # Almost everything in it is optional and off by default, so a non-root
  # LaunchAgent needs only two edits: point the schema and log directory under
  # the Homebrew prefix. The serial device is already unset; the service supplies
  # it with -d {} at launch.
  def install_config
    (var/"log/satpulse").mkpath

    config = buildpath/"configs/satpulse.toml"
    inreplace config do |s|
      s.gsub!(/^#:schema .*/, "#:schema #{opt_prefix}/share/satpulse/config-schema.json")
      s.gsub!(/^#dir = .*/, "dir = \"#{var}/log/satpulse\"")
    end

    # Do not overwrite an existing config on upgrade; user edits survive.
    etc.install config => "satpulse.toml" unless (etc/"satpulse.toml").exist?
  end
end
