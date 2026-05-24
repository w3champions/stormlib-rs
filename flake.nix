{
  description = "stormlib-rs — Rust bindings for StormLib (native Linux + Linux→Windows MSVC cross-compile)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # fenix reads rust-toolchain.toml directly via fromToolchainFile, so the
    # nix-built toolchain and any rustup-driven toolchain pick from the same
    # source of truth — no drift between the cross build, the devshell, and
    # a future CI runner.
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      fenix,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Pinned by ./rust-toolchain.toml. The sha256 covers the full resolved
      # toolchain bundle (rustc + cargo + rust-std for both targets +
      # rustfmt + clippy); bumping the channel or targets in the toml will
      # invalidate this hash and nix will print the new one.
      rustToolchain = fenix.packages.${system}.fromToolchainFile {
        file = ./rust-toolchain.toml;
        sha256 = "sha256-gh/xTkxKHL4eiRXzWv8KP7vfjSk61Iq48x47BEDFgfk=";
      };

      # rustPlatform.buildRustPackage uses nixpkgs's rustc by default, which
      # only ships the host target. Both packages go through the pinned
      # fenix toolchain via this rustPlatform so the linux build, the
      # windows cross build, and the devshell all use the same rustc/cargo.
      rustPlatform = pkgs.makeRustPlatform {
        cargo = rustToolchain;
        rustc = rustToolchain;
      };

      # callPackage variant that injects our pinned rustPlatform in place of
      # nixpkgs's default, so the package files in ./nix can be written in
      # plain callPackage style without referring to fenix or any flake
      # input.
      callPackage = pkgs.lib.callPackageWith (pkgs // { inherit rustPlatform; });

      stormlibSrc = callPackage ./nix/stormlib-src.nix { };
      xwinSdk = callPackage ./nix/xwin-sdk.nix { };
      linuxPackage = callPackage ./nix/stormlib-linux.nix { inherit stormlibSrc; };
      windowsPackage = callPackage ./nix/stormlib-windows.nix { inherit stormlibSrc xwinSdk; };
    in
    {
      packages.${system} = {
        default = linuxPackage;
        linux = linuxPackage;
        windows = windowsPackage;
        inherit xwinSdk;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          rustToolchain
          cargo-xwin
          cmake
          pkg-config
          zlib
          bzip2
          llvmPackages.clang
          llvmPackages.lld
          llvmPackages.llvm
        ];

        shellHook = ''
          export XWIN_CACHE_DIR="$HOME/.cache/xwin"
          export CMAKE_POLICY_VERSION_MINIMUM=3.5
          echo "stormlib-rs devshell"
          echo "  native:  cargo build --release -p stormlib-sys"
          echo "  windows: cargo xwin build --release --target x86_64-pc-windows-msvc -p stormlib-sys"
        '';
      };
    };
}
