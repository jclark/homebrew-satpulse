require_relative "../lib/satpulse_formula"

class SatpulsePre < Formula
  include SatpulseFormula

  desc "Integrated GPS timing daemon and configuration tool (prerelease channel)"
  homepage "https://github.com/jclark/satpulse"
  # Rolling "latest at >= prerelease stability" channel. Pins a bare revision (any
  # commit on master) with an explicit, monotonically increasing version so
  # `brew upgrade` fires. Re-pointing it is a two-line edit: new revision, bumped
  # version. The version reuses the Linux date convention minus the leading "v";
  # Homebrew parses "pre" as a prerelease token and orders by the trailing date.
  # (An @-versioned line such as satpulse@0.3 -- which would carry users in place
  # 0.3-pre -> 0.3 -> 0.3.1 -- is separate Future work.)
  url "https://github.com/jclark/satpulse.git",
      revision: "9cda46e62837acbf5924890e050299c9a1b16187"
  version "0.3-pre-20260831"
end
