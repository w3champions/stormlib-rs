extern crate cmake;

use std::env;
use std::path::Path;

fn main() {
  // Gets StormLib source path from env STORMLIB_DIR
  let stormlib_path = env::var("STORMLIB_DIR").unwrap_or("../../deps/StormLib".to_string());

  println!("cargo:rerun-if-changed={}", stormlib_path);

  // Builds StormLib using cmake
  let mut cfg = cmake::Config::new(&stormlib_path);

  if env::var("CARGO_CFG_TARGET_OS").unwrap() == "windows" {
    cfg.cxxflag("-D UNICODE").cxxflag("-D _UNICODE");

    // StormLib compiles its bundled zlib 1.2.5 on Windows, under zlib's own
    // symbol names. MSVC binds a reference to whichever static library on the
    // link line defines the name first, so once a downstream crate also links
    // libz-sys (or CascLib, with its own zlib 1.2.11), StormLib's
    // `inflate*`/`deflate*` calls can land in that copy instead. libz-sys built
    // without its `libc` feature defines Z_SOLO, which has no default
    // allocator, and StormLib (de)compresses with `zalloc = NULL`, so every
    // zlib-compressed MPQ sector fails. Always build the bundled libraries and
    // give every zlib symbol a `storm_` prefix.
    cfg.define("STORM_USE_BUNDLED_LIBRARIES", "ON");
    for flag in zlib_rename_flags(&Path::new(&stormlib_path).join("src/zlib/zconf.h"), "storm") {
      cfg.cflag(&flag).cxxflag(&flag);
    }

    // Match Rust's +crt-static (the default for cargo-xwin builds): the
    // C/C++ objects must use the static CRT (/MT), or the link fails with
    // __declspec(dllimport) CRT symbols against static libcmt. StormLib's
    // older CMakeLists makes CMAKE_MSVC_RUNTIME_LIBRARY / CMP0091
    // unreliable, so override the per-config flags directly.
    if env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default() == "msvc" {
      cfg
        .define("CMAKE_C_FLAGS_RELEASE", "/MT /O2 /Ob2 /DNDEBUG")
        .define("CMAKE_CXX_FLAGS_RELEASE", "/MT /O2 /Ob2 /DNDEBUG");
    }
  }

  if env::var("CARGO_CFG_TARGET_OS").unwrap() == "macos" {
    cfg.cflag("-Wno-implicit-function-declaration");
  }

  let dst = cfg.define("BUILD_SHARED_LIBS", "OFF").build();

  let lib = dst.join("lib");

  // For gcc should link static storm first! (before adding -l flags)
  // That's very important and I've wasted an hour finding it >_<
  // source: https://stackoverflow.com/questions/29199107/c-lz-library-link-order-undefined-reference-to-symbol-inflateinit2
  println!("cargo:rustc-link-search=native={}", lib.display());

  if env::var("CARGO_CFG_TARGET_OS").unwrap() == "windows" {
    println!("cargo::rustc-link-lib=static=StormLib");
    println!("cargo:rustc-link-lib=user32");
  }

  if env::var("CARGO_CFG_TARGET_OS").unwrap() == "macos" {
    println!("cargo:rustc-link-lib=static=storm");
    println!("cargo:rustc-link-lib=dylib=c++");
    println!("cargo:rustc-link-lib=z");
    println!("cargo:rustc-link-lib=bz2");
  }

  if env::var("CARGO_CFG_TARGET_OS").unwrap() == "linux" {
    println!("cargo:rustc-link-lib=static=storm");
    println!("cargo:rustc-link-lib=stdc++");
    println!("cargo:rustc-link-lib=z");
    println!("cargo:rustc-link-lib=bz2");
  }
}

/// `-D<name>=<prefix>_<name>` for every symbol zlib's own `Z_PREFIX` block in
/// `zconf.h` renames (the API plus internals such as `inflate_fast`, `zcalloc`
/// and `_tr_*`), and for `z_errmsg`, which that block leaves alone. Z_PREFIX
/// itself is not used because it hard-codes the `z_` prefix, and two bundled
/// copies prefixed alike collide with each other. `gz*` is skipped: those
/// sources are not compiled, and zlib.h redefines some of them as
/// function-like macros.
fn zlib_rename_flags(zconf: &Path, prefix: &str) -> Vec<String> {
  let text = std::fs::read_to_string(zconf)
    .unwrap_or_else(|e| panic!("failed to read {}: {}", zconf.display(), e));
  let mut names: Vec<&str> = text
    .lines()
    .filter_map(|line| {
      let mut words = line.trim_start().strip_prefix('#')?.split_whitespace();
      match (words.next(), words.next(), words.next(), words.next()) {
        (Some("define"), Some(name), Some(value), None)
          if value.strip_prefix("z_") == Some(name) =>
        {
          Some(name)
        }
        _ => None,
      }
    })
    .filter(|name| !name.starts_with("gz"))
    .collect();
  assert!(
    names.contains(&"inflate") && names.contains(&"inflate_fast"),
    "unexpected Z_PREFIX list in {}",
    zconf.display()
  );
  names.push("z_errmsg");
  names.sort_unstable();
  names.dedup();
  names
    .into_iter()
    .map(|name| format!("-D{}={}_{}", name, prefix, name))
    .collect()
}
