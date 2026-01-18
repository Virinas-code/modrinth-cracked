{
  description = "Modrinth App";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
      ];
      forAllSystems =
        f:
        builtins.listToAttrs (
          map (system: {
            name = system;
            value = f system;
          }) systems
        );
    in
    rec {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        rec {
          modrinth-app-unwrapped =

            let
              gradle = pkgs.gradle_8.override { java = jdk; };
              jdk = pkgs.jdk17;
            in

            pkgs.rustPlatform.buildRustPackage (finalAttrs: {
              pname = "modrinth-app-unwrapped";
              version = "0.10.23";

              src = ./.;

              patches = [
                # `packages/app-lib/build.rs` requires a Gradle executable, but our flags
                # are injected through a bash function sourced by the stdenv :(
                #
                # So, re-implement said wrapper to have the same behavior when Gradle is ran in `build.rs`
                (pkgs.replaceVars ./gradle-from-path.patch {
                  # Yes, it has to be a shell wrapper
                  # https://github.com/NixOS/nixpkgs/issues/172583
                  gradle =
                    pkgs.runCommand "gradle-exe-wrapper-${gradle.version}"
                      { nativeBuildInputs = [ pkgs.makeShellWrapper ]; }
                      ''
                        makeShellWrapper ${pkgs.lib.getExe gradle} $out \
                          --add-flags "\''${NIX_GRADLEFLAGS_COMPILE:-}"
                      '';
                })

                # `gradle.fetchDeps` doesn't seem to pick up a few integrations here
                # Thankfully that's fine, since it's only for development
                ./remove-spotless.patch
              ];

              # Let the app know about our actual version number
              postPatch = ''
                substituteInPlace {apps/app,packages/app-lib}/Cargo.toml apps/app-frontend/package.json \
                  --replace-fail '1.0.0-local' '${finalAttrs.version}'
              '';

              cargoHash = "sha256-hWjoNwKA39YYhPSrQUNaM1nS+CtV9vff+aXpoQLPCOM=";
              mitmCache = gradle.fetchDeps {
                inherit (finalAttrs) pname;
                data = ./deps.json;
              };

              pnpmDeps = pkgs.fetchPnpmDeps {
                inherit (finalAttrs) pname version src;
                pnpm = pkgs.pnpm_9;
                fetcherVersion = 1;
                hash = "sha256-jLuI8qNJgFkuBbKuBNKGuk/6v62iY7fNZX2t3U3olk0=";
              };

              nativeBuildInputs = [
                pkgs.cacert # Required for turbo
                pkgs.cargo-tauri.hook
                pkgs.desktop-file-utils
                pkgs.gradle
                pkgs.nodejs
                pkgs.pkg-config
                pkgs.pnpmConfigHook
                pkgs.pnpm_9
              ]
              ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isDarwin [
                pkgs.makeBinaryWrapper
                pkgs.xcbuild
              ];

              buildInputs = [
                pkgs.openssl
              ]
              ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.webkitgtk_4_1;

              gradleFlags = [
                "-Dfile.encoding=utf-8"
                "--no-configuration-cache"
              ];

              dontUseGradleBuild = true;
              dontUseGradleCheck = true;

              # Tests fail on other, unrelated packages in the monorepo
              cargoTestFlags = [
                "--package"
                "theseus_gui"
              ];

              # Required for mitmCache
              __darwinAllowLocalNetworking = true;

              env = {
                TURBO_BINARY_PATH = pkgs.lib.getExe pkgs.turbo;
              };

              preGradleUpdate = ''
                cd packages/app-lib/java
              '';

              # Required for the exe wrapper above
              preBuild = ''
                local nixGradleFlags=()
                concatTo nixGradleFlags gradleFlags gradleFlagsArray
                export NIX_GRADLEFLAGS_COMPILE="''${nixGradleFlags[@]}"

                cp packages/app-lib/.env.prod packages/app-lib/.env
              '';

              postInstall =
                pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
                  makeBinaryWrapper "$out"/Applications/Modrinth\ App.app/Contents/MacOS/Modrinth\ App "$out"/bin/ModrinthApp
                ''
                + pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
                  desktop-file-edit \
                    --set-comment "Modrinth's game launcher" \
                    --set-key="StartupNotify" --set-value="true" \
                    --set-key="Categories" --set-value="Game;ActionGame;AdventureGame;Simulation;" \
                    --set-key="Keywords" --set-value="game;minecraft;mc;" \
                    --set-key="StartupWMClass" --set-value="ModrinthApp" \
                    $out/share/applications/Modrinth\ App.desktop
                '';

              passthru = {
                updateScript = pkgs.nix-update-script { };
              };

              meta = {
                description = "Modrinth's game launcher";
                longDescription = ''
                  A unique, open source launcher that allows you to play your favorite mods,
                  and keep them up to date, all in one neat little package
                '';
                homepage = "https://modrinth.com";
                license = with pkgs.lib.licenses; [
                  gpl3Plus
                  unfreeRedistributable
                ];
                maintainers = with pkgs.lib.maintainers; [ getchoo ];
                mainProgram = "ModrinthApp";
                platforms = with pkgs.lib; platforms.linux ++ platforms.darwin;
                # This builds on architectures like aarch64, but the launcher itself does not support them yet.
                # Darwin is the only exception
                # See https://github.com/modrinth/code/issues/776#issuecomment-1742495678
                broken = !pkgs.stdenv.hostPlatform.isx86_64 || !pkgs.stdenv.hostPlatform.isLinux;
                sourceProvenance = with pkgs.lib.sourceTypes; [
                  fromSource
                  binaryBytecode # mitm cache
                ];
              };
            });
          modrinth-app =
            # {
            #   lib,
            #   stdenv,
            #   addDriverRunpath,
            #   alsa-lib,
            #   flite,
            #   glib,
            #   glib-networking,
            #   gsettings-desktop-schemas,
            #   jdk25,
            #   jdk17,
            #   jdk21,
            #   jdk8,
            #   jdks ? [
            #     jdk8
            #     jdk17
            #     jdk21
            #     jdk25
            #   ],
            #   libGL,
            #   libjack2,
            #   libpulseaudio,
            #   modrinth-app-unwrapped,
            #   pipewire,
            #   symlinkJoin,
            #   udev,
            #   wrapGAppsHook4,
            #   xorg,
            # }:
            let
              jdks = [
                pkgs.jdk8
                pkgs.jdk17
                pkgs.jdk21
                pkgs.jdk25
              ];
            in

            pkgs.symlinkJoin {
              pname = "modrinth-app";
              inherit (modrinth-app-unwrapped) version;

              paths = [ modrinth-app-unwrapped ];

              strictDeps = true;

              nativeBuildInputs = [
                pkgs.glib
                pkgs.wrapGAppsHook4
              ];

              buildInputs = [
                pkgs.glib-networking
                pkgs.gsettings-desktop-schemas
              ];

              runtimeDependencies = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux (
                pkgs.lib.makeLibraryPath [
                  pkgs.addDriverRunpath.driverLink

                  # glfw
                  pkgs.libGL
                  pkgs.xorg.libX11
                  pkgs.xorg.libXcursor
                  pkgs.xorg.libXext
                  pkgs.xorg.libXrandr
                  pkgs.xorg.libXxf86vm

                  # lwjgl
                  (pkgs.lib.getLib pkgs.stdenv.cc.cc)

                  # narrator support
                  pkgs.flite

                  # openal
                  pkgs.alsa-lib
                  pkgs.libjack2
                  pkgs.libpulseaudio
                  pkgs.pipewire

                  # oshi
                  pkgs.udev
                ]
              );

              postBuild = ''
                gappsWrapperArgs+=(
                  --prefix PATH : ${pkgs.lib.makeSearchPath "bin/java" jdks}
                  ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
                    --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xorg.xrandr ]}
                    --set LD_LIBRARY_PATH $runtimeDependencies
                  ''}
                )

                glibPostInstallHook
                gappsWrapperArgsHook
                wrapGAppsHook
              '';

              meta = {
                inherit (modrinth-app-unwrapped.meta)
                  description
                  longDescription
                  homepage
                  license
                  maintainers
                  mainProgram
                  platforms
                  broken
                  ;
              };
            };
          default = modrinth-app;
        }
      );
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          jdks = [
            pkgs.jdk17
            pkgs.jdk8
            pkgs.jdk21
            pkgs.jdk25
          ];
        in
        {
          default = pkgs.mkShell rec {
            name = "Desktop App";
            inputsFrom = [
              self.packages."${system}".modrinth-app
              self.packages."${system}".modrinth-app-unwrapped
            ];
            TURBO_BINARY_PATH = pkgs.lib.getExe pkgs.turbo;
            TURBO_ENV_MODE = "loose"; # Honestly IDK.
            buildInputs = with pkgs; [ rust-analyzer ] ++ jdks;

            MODRINTH_URL = "https://modrinth.com/";
            MODRINTH_API_URL = "https://api.modrinth.com/v2/";
            MODRINTH_API_URL_V3 = "https://api.modrinth.com/v3/";
            MODRINTH_SOCKET_URL = "wss://api.modrinth.com/";
            MODRINTH_LAUNCHER_META_URL = "https://launcher-meta.modrinth.com/";

            # https://github.com/tauri-apps/tauri/issues/14187#issuecomment-3299825484
            XDG_DATA_DIRS = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:$XDG_DATA_DIRS";
            GIO_MODULE_DIR = "${pkgs.glib-networking}/lib/gio/modules/";

            # https://wiki.nixos.org/wiki/Rust#Shell.nix_example
            RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";

            # https://github.com/NixOS/nixpkgs/issues/60919#issue-440333621
            hardeningDisable = [ "fortify" ];

            # runtimeDependencies = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux (
            #   pkgs.lib.makeLibraryPath [
            #     pkgs.addDriverRunpath.driverLink

            #     # glfw
            #     pkgs.libGL
            #     pkgs.xorg.libX11
            #     pkgs.xorg.libXcursor
            #     pkgs.xorg.libXext
            #     pkgs.xorg.libXrandr
            #     pkgs.xorg.libXxf86vm

            #     # lwjgl
            #     (pkgs.lib.getLib pkgs.stdenv.cc.cc)

            #     # narrator support
            #     pkgs.flite

            #     # openal
            #     pkgs.alsa-lib
            #     pkgs.libjack2
            #     pkgs.libpulseaudio
            #     pkgs.pipewire

            #     # oshi
            #     pkgs.udev
            #   ]
            # );
            LD_LIBRARY_PATH = "${packages."${system}".modrinth-app.runtimeDependencies}";
          };
        }
      );
      #   apps = forAllSystems (
      #     system:
      #     let
      #       pkgs = import nixpkgs {
      #         inherit system;
      #         config.allowUnfree = true;
      #       };
      #     in
      #     rec {
      #       modrinth-app = {
      #         type = "app";
      #         program = "${self.packages.${system}.modrinth-app}/bin/ModrinthApp";
      #         meta = self.packages.${system}.modrinth-app.meta;
      #       };
      #       default = modrinth-app;
      #     }
      #   );
    };
}
