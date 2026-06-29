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
      # The job runs the satpulse-service wrapper (written by def install) rather
      # than invoking find-serial directly, so device selection lives in
      # etc/satpulse.env -- a config file preserved across upgrades -- instead of
      # this plist, which brew regenerates on every install.
      #
      # Deliberately no keep_alive: the daemon runs once when the user starts the
      # service. Auto-restart is unsafe today -- find-serial matches any USB
      # serial device, so a respawn could grab an unrelated device (likely at the
      # wrong baud rate). Re-introducing restart needs a find-serial --wait that
      # blocks on a specific VID/PID first (base-repo work).
      run opt_libexec/"satpulse-service"
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
    install_service_wrapper
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
  # the Homebrew prefix. The serial device is left unset here; the launchd
  # service always passes one with -d (from find-serial, or SATPULSE_DEVICE in
  # satpulse.env), so the toml device setting is unused under the service.
  def install_config
    (var/"log/satpulse").mkpath

    config = buildpath/"configs/satpulse.toml"
    inreplace config do |s|
      s.gsub!(/^#:schema .*/, "#:schema #{opt_prefix}/share/satpulse/config-schema.json")
      s.gsub!(/^#dir = .*/, "dir = \"#{var}/log/satpulse\"")
      # The stock comment block above #device is systemd-specific; on macOS the
      # launchd service sets the device itself. Replace whatever comment lines
      # precede #device, rather than matching exact wording.
      s.sub!(
        /(?:^#.*\n)+(?=#device)/,
        "# Unused under the launchd service, which always passes -d (from\n" \
        "# find-serial, or SATPULSE_DEVICE in satpulse.env). Set the device\n" \
        "# there, not here.\n",
      )
    end

    # Do not overwrite an existing config on upgrade; user edits survive.
    etc.install config => "satpulse.toml" unless (etc/"satpulse.toml").exist?
  end

  # The launchd job runs this wrapper instead of calling find-serial directly,
  # so device selection is configured in etc/satpulse.env (a config file that
  # survives upgrades) rather than the plist (regenerated on every install).
  # Paths are baked in at install time; the script is overwritten on each
  # install, so path/logic fixes ship automatically and users never edit it.
  def install_service_wrapper
    (libexec/"satpulse-service").write <<~SH
      #!/bin/bash
      set -a
      if [ -r #{etc}/satpulse.env ]; then
        . #{etc}/satpulse.env
      fi
      set +a
      if [ -n "$SATPULSE_DEVICE" ]; then
        exec #{opt_sbin}/satpulsed -f #{etc}/satpulse.toml -d "$SATPULSE_DEVICE"
      fi
      exec #{opt_bin}/find-serial $SATPULSE_FIND_SERIAL_OPTS --exec -- #{opt_sbin}/satpulsed -f #{etc}/satpulse.toml -d '{}'
    SH
    (libexec/"satpulse-service").chmod 0555

    # Default env config; like satpulse.toml, do not overwrite user edits.
    return if (etc/"satpulse.env").exist?

    (buildpath/"satpulse.env").write <<~ENV
      # satpulse.env -- configuration for the satpulse launchd service.
      # Sourced as a shell script (NAME=value, no spaces around =, # comments).
      # Apply changes with:  brew services restart satpulse   (or satpulse-pre)

      # Serial device. Empty (the default) = auto-discover with find-serial.
      # Set to a /dev/cu.* path to use that device and skip find-serial.
      SATPULSE_DEVICE=

      # Extra find-serial options (used only when SATPULSE_DEVICE is empty), e.g.
      # to pin one USB device when several are present. Find ids by running
      # find-serial with no arguments.
      #   SATPULSE_FIND_SERIAL_OPTS="--vid 1546 --pid 01A9"
      SATPULSE_FIND_SERIAL_OPTS=
    ENV
    etc.install buildpath/"satpulse.env"
  end

  # Printed before Homebrew's auto-generated "brew services" block; mirrors its
  # phrasing, adding the edit step and the on-demand `run` form.
  def caveats
    <<~EOS
      You should edit the config file at #{etc}/satpulse.toml before running #{name}.

      The serial device is auto-discovered with find-serial. To pin a device or
      pass find-serial options, edit #{etc}/satpulse.env.

      To start #{full_name} now and not restart at login:
        brew services run #{full_name}
    EOS
  end
end
