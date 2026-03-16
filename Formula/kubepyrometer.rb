# Homebrew formula for KubePyrometer
# Install:
#   brew tap spectronauts/kubepyrometer
#   brew install kubepyrometer

class Kubepyrometer < Formula
  desc "Kubernetes control-plane load-testing harness"
  homepage "https://github.com/spectronauts/KubePyrometer"
  url "https://github.com/spectronauts/KubePyrometer/releases/download/v0.3.0-preview/kubepyrometer-0.3.0-preview.tar.gz"
  sha256 "e583def53d02bc799f479be088aa5fdb8aa0791d82bf8cd5fad26eb6d29ede93"
  license "Apache-2.0"

  depends_on "bash"
  depends_on "kubectl" => :recommended

  def install
    kp = libexec/"kubepyrometer"
    kp.install Dir["v0/scripts", "v0/workloads", "v0/templates",
                   "v0/manifests", "v0/configs", "v0/images",
                   "v0/config.yaml", "v0/run.sh"]
    kp.install "VERSION"

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
