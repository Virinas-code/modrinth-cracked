let
  pkgs = import <nixpkgs> { };
in
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    pkg-config
    gobject-introspection
    cargo
    cargo-tauri
    nodejs
    pnpm
    jemalloc
  ];

  buildInputs = with pkgs; [
    at-spi2-atk
    atkmm
    cairo
    gdk-pixbuf
    glib
    gtk3
    harfbuzz
    librsvg
    libsoup_3
    pango
    webkitgtk_4_1
    openssl
    jemalloc
    glib-networking
    rustfmt
    jdk8
    jdk17
    jdk21
  ];
  shellHook = ''
    export NIX_HARDENING_ENABLE=
    export GIO_MODULE_DIR=${pkgs.glib-networking}/lib/gio/modules/
    export RUST_SRC_PATH="${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}"
  ''; # See https://github.com/tikv/jemallocator/issues/108#issuecomment-2642756257 & https://github.com/NixOS/nixpkgs/issues/101979 ; See https://www.reddit.com/r/NixOS/comments/k1lt7c/tlsssl_support_not_available_install/
}
