require_relative "../lib/satpulse_formula"

class Satpulse < Formula
  include SatpulseFormula

  desc "Integrated GPS timing daemon and configuration tool"
  homepage "https://github.com/jclark/satpulse"
  # Head-only for now. A `stable` block (url ...git, tag: "v0.3", revision: ...)
  # is added at the v0.3 release; until then use `brew install --HEAD`.
  head "https://github.com/jclark/satpulse.git", branch: "master"
end
