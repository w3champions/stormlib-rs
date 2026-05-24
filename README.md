[![Rust](https://github.com/wc3tools/stormlib-rs/actions/workflows/rust.yml/badge.svg)](https://github.com/wc3tools/stormlib-rs/actions/workflows/rust.yml)

## Rust [StormLib](https://github.com/ladislav-zezula/StormLib) binding for working with Blizzard MPQ archives

```rust
fn test_read_utf8() {
  let mut archive = Archive::open(
    "../../samples/中文.w3x",
    OpenArchiveFlags::MPQ_OPEN_NO_LISTFILE | OpenArchiveFlags::MPQ_OPEN_NO_ATTRIBUTES,
  )
  .unwrap();
  let mut f = archive.open_file("war3map.j").unwrap();
  assert_eq!(
    f.read_all().unwrap(),
    std::fs::read("../../samples/war3map.j").unwrap()
  );
}
```

## Building

### With cargo (any platform)

```sh
git submodule update --init --recursive   # vendored StormLib in ./deps
cargo build --release -p stormlib-sys
```

The `cmake` build script under `crates/stormlib-sys/build.rs` drives an
in-tree CMake build of `deps/StormLib` and links the resulting static
archive. You need `cmake`, a C/C++ toolchain, and the system `zlib` /
`bzip2` headers on PATH. On NixOS, prefer the flake (below).

### With Nix

The flake provides reproducible builds for both native Linux and the
Linux → Windows MSVC cross. The Rust toolchain is pinned via
[`rust-toolchain.toml`](./rust-toolchain.toml) and resolved through
[fenix](https://github.com/nix-community/fenix), so the devshell, the
sandboxed nix builds, and any future rustup user all pick up the same
`rustc`/`cargo`.

```sh
# Native Linux: ships ./result/lib/libstorm.a
nix build .#linux        # or just `nix build`

# Linux → Windows MSVC cross-compile: ships ./result/lib/StormLib.lib
nix build .#windows
```

Tests run as part of `nix build .#linux` (raw FFI sanity + high-level
read against `samples/test_tft.w3x`). The Windows build is build-only —
running the cross-compiled tests would require to pull `wine` into the sandbox.

#### Devshell

```sh
nix develop
# inside the devshell:
cargo build   --release -p stormlib-sys
cargo test    --workspace --exclude stormlib-bindgen
cargo clippy  --workspace --exclude stormlib-bindgen --all-targets
# Windows cross via cargo-xwin (uses ~/.cache/xwin on first run):
cargo xwin build  --release --target x86_64-pc-windows-msvc -p stormlib-sys
cargo xwin clippy --workspace --exclude stormlib-bindgen \
                  --all-targets --target x86_64-pc-windows-msvc
```

### How the Windows cross-compile works

The flake builds the MSVC CRT + Windows SDK once as a fixed-output
derivation via [`xwin`](https://github.com/Jake-Shadle/xwin) (see the
`xwinSdk` derivation in `flake.nix`) and feeds the splatted output into
[`cargo-xwin`](https://github.com/rust-cross/cargo-xwin) at build time.
The sandboxed build itself stays fully offline.

The cross target is pinned to `x86_64-pc-windows-msvc`. The `XWIN_ARCH`
env in the windows build derivation must match the `--arch` passed to
the xwinSdk FOD; both are driven from the single `xwinArch` binding in
`flake.nix`.

### Bumping the vendored StormLib

The StormLib source is fetched in the flake as a `fetchFromGitHub` FOD
pinned by commit + hash, and locally as a git submodule under
`./deps/StormLib`. To bump:

1. Update the submodule (`git -C deps/StormLib fetch && git -C deps/StormLib checkout <rev>`).
2. Update `stormlibSrc.rev` in `flake.nix` to match, and set
   `stormlibSrc.hash` to `lib.fakeHash`; rebuild to get the real hash.
3. If StormLib's public headers changed, regenerate the FFI bindings
   (the `bindings_{linux,windows,macos}.rs` files in
   `crates/stormlib-sys/src/`) by running the `stormlib-bindgen` crate
   on each target platform.

### Bumping the Rust toolchain

Edit `rust-toolchain.toml`, then rebuild any nix package; fenix will
fail with a `sha256` mismatch and print the new hash to paste into
`rustToolchain` in `flake.nix`.
