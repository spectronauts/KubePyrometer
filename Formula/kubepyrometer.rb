# Homebrew formula for KubePyrometer
# Install:
#   brew tap <org>/kubepyrometer https://github.com/<org>/KubePyrometer
#   brew install kubepyrometer
#
# Or from a dedicated tap repo:
#   brew tap <org>/tap
#   brew install kubepyrometer

class Kubepyrometer < Formula
  desc "Kubernetes control-plane load-testing harness"
  homepage "https://github.com/<org>/KubePyrometer"
  # TODO: update URL and sha256 after first release
  url "https://github.com/<org>/KubePyrometer/releases/download/v0.1.0/kubepyrometer-0.1.0.tar.gz"
  sha256 "PLACEHOLDER"
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
