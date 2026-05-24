{ fetchFromGitHub }:

# StormLib C++ source. Pinned to the same revision as the deps/StormLib git
# submodule (44362ca, v9.20-407-g44362ca). The Rust crates' build.rs reads
# this path via STORMLIB_DIR so the nix build doesn't require the submodule
# to be initialized in the source tree.
fetchFromGitHub {
  owner = "ladislav-zezula";
  repo = "StormLib";
  rev = "44362ca0a07a6930ce8124dfb95b8fb1a9849644";
  hash = "sha256-2lnyL5HfbY/hfKw72jvRgRGFZpwDPRBqA6+sH9QuYrI=";
}
