require_relative "../lib/satpulse_formula"

class Satpulse < Formula
  include SatpulseFormula

  desc "Integrated GPS timing daemon and configuration tool"
  homepage "https://github.com/jclark/satpulse"
  url "https://github.com/jclark/satpulse.git",
      tag:      "v0.3",
      revision: "506c53a8c302ff00a66f8727a0b4a0df08ae4dc2"
  head "https://github.com/jclark/satpulse.git", branch: "master"

  conflicts_with "satpulse-pre", because: "both install the same files"
end
