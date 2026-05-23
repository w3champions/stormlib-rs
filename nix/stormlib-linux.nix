{
  lib,
  rustPlatform,
  cmake,
  zlib,
  bzip2,
  stdenv,
  callPackage,
  # Vendored StormLib C++ source tree. Override to point at a different
  # revision or a local checkout.
  stormlibSrc ? callPackage ./stormlib-src.nix { },
  version ? "0.1.2",
  # Cmake-driven build of the vendored StormLib needs an older policy floor
  # than CMake 4 ships with.
  cmakePolicyMinimum ? "3.5",
}:

let
  src = ../.;
in

# Native Linux: rustPlatform.buildRustPackage drives a fully sandboxed,
# offline cargo build against the committed Cargo.lock. The build is scoped
# to stormlib-sys so cargo doesn't pull stormlib-bindgen (a dev-only tool
# that drags bindgen + clang-sys + ~60MB of rlibs into the build). The only
# artifact shipped is libstorm.a from the cmake subbuild, mirroring what
# stormlib-windows.nix does with StormLib.lib.
rustPlatform.buildRustPackage {
  pname = "stormlib-rs";
  inherit version src;

  cargoLock.lockFile = src + "/Cargo.lock";

  cargoBuildFlags = [
    "-p"
    "stormlib-sys"
  ];

  # Tests live in stormlib-sys (raw FFI sanity check) and stormlib (high-
  # level read against samples/test_tft.w3x). stormlib-bindgen is dev-only
  # and pulls bindgen + clang-sys, so exclude it from the test run too.
  cargoTestFlags = [
    "--workspace"
    "--exclude"
    "stormlib-bindgen"
  ];

  # rustc doesn't rpath buildInputs into the test binaries, so every
  # dynamically-linked C dep (libstdc++, libz, libbz2) is missing at
  # test-execution time. Point the loader at them for the check phase only —
  # the installed artifact (libstorm.a) is static and unaffected.
  preCheck =
    let
      libraries = lib.makeLibraryPath [
        stdenv.cc.cc.lib
        zlib
        bzip2
      ];
    in
    ''
      export LD_LIBRARY_PATH="${libraries}"
    '';

  nativeBuildInputs = [ cmake ];
  buildInputs = [
    zlib
    bzip2
    # build.rs emits `cargo:rustc-link-lib=stdc++` (dynamic). Without this,
    # the test binary builds fine but the sandbox loader can't find
    # libstdc++.so.6 at test-execution time.
    stdenv.cc.cc.lib
  ];

  env = {
    CMAKE_POLICY_VERSION_MINIMUM = cmakePolicyMinimum;
    STORMLIB_DIR = toString stormlibSrc;
  };

  # cmake here is invoked by stormlib-sys/build.rs via the cmake crate; the
  # package itself isn't a CMake project, so suppress the default configure
  # hook.
  dontUseCmakeConfigure = true;

  # Skip the default install hook (which would copy binaries from
  # target/release/ into $out/bin/) and ship just the static library. Rust
  # consumers cargo-build from source anyway; the rlibs are tied to this
  # exact rustc version and aren't redistributable.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    # nixpkgs's rustPlatform passes an explicit --target, so cargo writes
    # under target/<triple>/release/ rather than target/release/. The cmake
    # crate places its installed output at .../out/lib/.
    cp target/*/release/build/stormlib-sys-*/out/lib/libstorm.a $out/lib/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Static StormLib (libstorm.a) built against the workspace's vendored source";
    homepage = "https://github.com/ladislav-zezula/StormLib";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
