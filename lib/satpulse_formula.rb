# typed: strict
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
      # than invoking find-serial directly, so its use of find-serial is
      # configured in etc/find-serial.env -- a config file preserved across
      # upgrades -- instead of this plist, which brew regenerates on every install.
      #
      # Deliberately no keep_alive: the daemon runs once when the user starts
      # the service. The blocker is not upstream -- find-serial has had --wait
      # since satpulse ff6de9ac, and it honours --vid/--pid/--serial/--location
      # -- it is that restart cannot be made conditional on the user having
      # pinned a device:
      #   - the shipped default leaves FIND_SERIAL_OPTS empty, so find-serial
      #     matches any USB serial device and a respawn could grab an unrelated
      #     one (likely at the wrong baud rate);
      #   - keep_alive lives in this plist, which is regenerated from here on
      #     every install, so it cannot be turned on per user the way
      #     find-serial.env settings can;
      #   - the wrapper does not pass --wait, so with no device present
      #     find-serial exits EX_UNAVAILABLE at once and keep_alive would just
      #     throttle-loop; passing --wait unfiltered would instead block and
      #     hand satpulsed whichever device turned up next.
      # Restart therefore needs wrapper-side work here (wait/re-exec only when
      # FIND_SERIAL_OPTS identifies a device), not a base-repo change.
      run opt_libexec/"satpulse-service"
      log_path var/"log/satpulse/launchd.out.log"
      error_log_path var/"log/satpulse/launchd.err.log"
    end

    # The full hardware-free smoke test: CI just runs `brew test` on each
    # channel, so this is the single place the checks live. The Go tools print
    # --version/--help to stderr, so redirect it into the captured stdout;
    # without the 2>&1 shell_output sees an empty string. find-serial gets
    # --help (deterministic exit 0) because its listing mode depends on IOKit
    # enumeration, which is not reliable on a headless runner.
    formula.test do
      assert_match "satpulse", shell_output("#{bin}/satpulsetool --version 2>&1")
      assert_match "satpulse", shell_output("#{bin}/satpulsewb --version 2>&1")
      assert_match "--config-file", shell_output("#{sbin}/satpulsed --help 2>&1")
      assert_match "usage: find-serial", shell_output("#{bin}/find-serial --help 2>&1")
    end
  end

  def install
    # Build the Go binaries and the man pages (`make` on macOS dispatches to
    # Makefile.unix, which uses pandoc for the man pages -- hence the build
    # dep). The embedded version is derived from git, so the build dir must be
    # a real clone with .git (it is, via the git download strategy).
    system "make"

    # make install lays out everything except find-serial: binaries into
    # sbin/bin, man pages, gpsmsg files (share/satpulse) and the config schema
    # (share/doc/satpulse) -- paths shared by both channels, unlike pkgshare or
    # doc, which embed the formula name. sysconfdir=#{etc} makes it write the
    # default satpulse.toml to HOMEBREW_PREFIX/etc, outside the keg, so it
    # survives upgrades; the target skips the config when the file already
    # exists, so user edits are preserved. Record freshness first: the macOS
    # config edits below must apply only to a file make install just wrote.
    config_is_fresh = !(etc/"satpulse.toml").exist?
    system "make", "install", "prefix=#{prefix}", "sysconfdir=#{etc}"

    # make install bakes #{prefix} -- the versioned keg path -- into these two
    # man pages (the gpsmsg dir in satpulsetool-gps.1, the schema dir in
    # satpulse.toml.5); rewrite to the stable opt_prefix so nothing points into
    # the Cellar (the lz4/ncurses pattern in homebrew-core). satpulsed.8 is not
    # in the list: it only gets sysconfdir baked in, which is already the
    # stable #{etc} -- and inreplace fails when its pattern is absent.
    inreplace [man1/"satpulsetool-gps.1", man5/"satpulse.toml.5"], prefix, opt_prefix

    # find-serial is a standalone Darwin C tool with its own Makefile, built
    # separately (Makefile.unix deliberately holds no platform-specific
    # knowledge, so macOS bits stay here).
    system "make", "-C", "macos"
    bin.install "macos/find-serial"

    (var/"log/satpulse").mkpath
    localize_config if config_is_fresh
    install_service_wrapper
  end

  # macOS edits to the default config that make install just wrote to
  # etc/satpulse.toml: point the #:schema line at opt_prefix (make install
  # baked in the versioned keg path), the log directory under var, and replace
  # the systemd-specific comment above #device. Only ever applied to a freshly
  # written file -- an existing config is the user's copy, which may not
  # contain these patterns, and inreplace fails the build when a pattern is
  # absent. The serial device is left unset; by default the launchd service
  # auto-discovers it with find-serial and passes it as -d. To use a fixed
  # device, set it in the config and disable find-serial in find-serial.env.
  def localize_config
    inreplace etc/"satpulse.toml" do |s|
      s.gsub!(/^#:schema .*/, "#:schema #{opt_prefix}/share/doc/satpulse/config-schema.json")
      s.gsub!(/^#dir = .*/, "dir = \"#{var}/log/satpulse\"")
      # The stock comment block above #device is systemd-specific; on macOS the
      # launchd service sets the device itself. Replace whatever comment lines
      # precede #device, rather than matching exact wording.
      s.sub!(
        /(?:^#.*\n)+(?=#device)/,
        "# The launchd service auto-discovers the device with find-serial and\n" \
        "# passes it as -d. To use this setting instead, disable find-serial in\n" \
        "# find-serial.env (set FIND_SERIAL_DISABLE).\n",
      )
    end
  end

  # The launchd job runs this wrapper instead of calling find-serial directly,
  # so its use of find-serial is configured in etc/find-serial.env (a config
  # file that survives upgrades) rather than the plist (regenerated on every
  # install). Paths are baked in at install time; the script is overwritten on
  # each install, so path/logic fixes ship automatically and users never edit it.
  def install_service_wrapper
    (libexec/"satpulse-service").write <<~SH
      #!/bin/bash
      set -a
      if [ -r #{etc}/find-serial.env ]; then
        . #{etc}/find-serial.env
      fi
      set +a
      if [ -n "$FIND_SERIAL_DISABLE" ]; then
        exec #{opt_sbin}/satpulsed -f #{etc}/satpulse.toml
      fi
      exec #{opt_bin}/find-serial $FIND_SERIAL_OPTS --exec -- #{opt_sbin}/satpulsed -f #{etc}/satpulse.toml -d '{}'
    SH
    (libexec/"satpulse-service").chmod 0555

    # Default env config; like satpulse.toml, do not overwrite user edits.
    return if (etc/"find-serial.env").exist?

    (buildpath/"find-serial.env").write <<~ENV
      # find-serial.env -- configures the satpulse launchd service's use of
      # find-serial (USB serial device auto-discovery).
      # Sourced as a shell script (NAME=value, no spaces around =, # comments).
      # Apply changes with:  brew services restart satpulse   (or satpulse-pre)

      # By default the service auto-discovers the USB serial device with
      # find-serial. Set to any non-empty value to disable that and use the
      # `device` configured in satpulse.toml instead.
      FIND_SERIAL_DISABLE=

      # Extra find-serial options (when enabled), e.g. to pin one USB device when
      # several are present. Find ids by running find-serial with no arguments.
      #   FIND_SERIAL_OPTS="--vid 1546 --pid 01A9"
      FIND_SERIAL_OPTS=
    ENV
    etc.install buildpath/"find-serial.env"
  end

  # Printed before Homebrew's auto-generated "brew services" block; mirrors its
  # phrasing, adding the edit step and the on-demand `run` form.
  def caveats
    <<~EOS
      You should edit the config file at #{etc}/satpulse.toml before running #{name}.

      The serial device is auto-discovered with find-serial. To pass find-serial
      options or disable it (and set the device in satpulse.toml), edit
      #{etc}/find-serial.env.

      To start #{full_name} now and not restart at login:
        brew services run #{full_name}
    EOS
  end
end
