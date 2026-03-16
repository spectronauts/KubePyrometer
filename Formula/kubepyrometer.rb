# Homebrew formula for KubePyrometer
# Install:
#   brew tap spectronauts/kubepyrometer https://github.com/spectronauts/KubePyrometer
#   brew install kubepyrometer
#
# Or from a dedicated tap repo:
#   brew tap spectronauts/tap
#   brew install kubepyrometer

class Kubepyrometer < Formula
  desc "Kubernetes control-plane load-testing harness"
  homepage "https://github.com/spectronauts/KubePyrometer"
  url "https://github.com/spectronauts/KubePyrometer/releases/download/v0.3.0-preview/kubepyrometer-0.3.0-preview.tar.gz"
  sha256 "8d0e575a4eac0b81ecfbe97a70143397cbbe65da665b1f4f7dc6ad9e14faad6a"
  license "Apache-2.0"

  depends_on "bash"
  depends_on "kubectl" => :recommended

  def install
    libexec.install Dir["v0/scripts", "v0/workloads", "v0/templates",
                        "v0/manifests", "v0/configs", "v0/images",
                        "v0/config.yaml", "v0/run.sh"]
    libexec.install "VERSION"

    # The main CLI resolves KUBEPYROMETER_HOME from its install location.
    bin.install "kubepyrometer"
  end

  def caveats
    <<~EOS
      To get started:
        kubepyrometer init           # generate a config file in the current directory
        kubepyrometer run            # run with default settings
        kubepyrometer run -p large   # run with the 'large' cluster profile

      Run output is saved to ./runs/<timestamp>/ by default.
      See kubepyrometer help for all commands.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/kubepyrometer version")
  end
end
