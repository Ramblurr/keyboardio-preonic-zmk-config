{
  description = "Local ZMK build environment for the Keyboardio Preonic";
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # tracks nixpkgs unstable branch
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    devenv.url = "https://flakehub.com/f/ramblurr/nix-devenv/*";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs =
    inputs@{
      self,
      devenv,
      devshell,
      ...
    }:
    devenv.lib.mkFlake ./. {
      inherit inputs;
      withOverlays = [
        devshell.overlays.default
        devenv.overlays.default
      ];
      devShell =
        pkgs:
        pkgs.devshell.mkShell {
          imports = [
            devenv.capsules.base
          ];
          commands = [
            {
              name = "zmk-init";
              help = "Initialize/update the local workspace from config/west.yml";
              command = ''
                set -euo pipefail
                mkdir -p "$PRJ_ROOT/.zmk/config"
                cp "$PRJ_ROOT/config/west.yml" "$PRJ_ROOT/.zmk/config/west.yml"
                cd "$PRJ_ROOT/.zmk"
                if [[ ! -d .west ]]; then
                  west init -l config
                fi
                west update
              '';
            }
            {
              name = "zmk-build";
              help = "Build Preonic firmware (run zmk-init first)";
              command = ''
                set -euo pipefail
                cd "$PRJ_ROOT/.zmk"
                # Avoid west's wrapper prepending a Python without our build modules.
                python3 -m west build -s zmk/app -d build/keyboardio_preonic \
                  -b keyboardio_preonic -p auto "$@" -- \
                  -DZephyr_DIR="$PRJ_ROOT/.zmk/zephyr/share/zephyr-package/cmake" \
                  -DZMK_CONFIG="$PRJ_ROOT/config" \
                  -DZMK_EXTRA_MODULES="$PRJ_ROOT" \
                  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
              '';
            }
            {
              name = "zmk-keymap";
              help = "Export the current QWERTY keymap to out/ as SVG, PNG and PDF";
              command =
                let
                  drawerConfig = pkgs.writeText "preonic-keymap-drawer.yaml" ''
                    draw_config:
                      footer_text: "QWERTY / US | Rotary encoder: volume | Triangle: inherit lower layer | Pink: held layer key"
                    parse_config:
                      raw_binding_map:
                        "&bootloader": "Bootloader"
                        "&studio_unlock": "Unlock Studio"
                      zmk_keycode_map:
                        C_PP: "Play/Pause"
                        LC(LS(LA(LGUI))): "Hyper"
                        LGUI: "Super"
                        KP_DIVIDE: "KP /"
                        KP_MULTIPLY: "KP *"
                        KP_MINUS: "KP -"
                        KP_PLUS: "KP +"
                        KP_EQUAL: "KP ="
                        GRAVE: "`"
                        MINUS: "-"
                        SEMI: ";"
                        SQT: "'"
                        COMMA: ","
                        PERIOD: "."
                        SLASH: "/"
                        BSLH: "\\"
                        LBKT: "["
                        RBKT: "]"
                        LS(LBKT): "{"
                        LS(RBKT): "}"
                  '';
                in
                ''
                  set -euo pipefail
                  cd "$PRJ_ROOT"
                  layout=.zmk/keyboardio-preonic-zmk-module/boards/arm/keyboardio_preonic/keyboardio_preonic-layouts.dtsi
                  if [[ ! -f "$layout" ]]; then
                    echo "Missing Preonic layout: run zmk-init first." >&2
                    exit 1
                  fi
                  mkdir -p out
                  ${pkgs.keymap-drawer}/bin/keymap -c ${drawerConfig} parse \
                    -z config/keyboardio_preonic.keymap -o out/qwerty.yaml
                  ${pkgs.keymap-drawer}/bin/keymap -c ${drawerConfig} draw \
                    out/qwerty.yaml -d "$layout" -l mit_layout -o out/qwerty.svg
                  ${pkgs.inkscape}/bin/inkscape out/qwerty.svg \
                    --export-type=png --export-filename=out/qwerty.png \
                    --export-dpi=192 --export-background=white --export-background-opacity=1
                  ${pkgs.inkscape}/bin/inkscape out/qwerty.svg \
                    --export-type=pdf --export-filename=out/qwerty.pdf
                  printf 'Exported %s/out/qwerty.{svg,png,pdf}\n' "$PRJ_ROOT"
                '';
            }
          ];
          env = [
            {
              name = "ZEPHYR_TOOLCHAIN_VARIANT";
              value = "gnuarmemb";
            }
            {
              name = "GNUARMEMB_TOOLCHAIN_PATH";
              value = "${pkgs.gcc-arm-embedded-13}";
            }
          ];
          packages = with pkgs; [
            cmake
            ninja
            gnumake
            git
            dtc
            gcc-arm-embedded-13
            protobuf
            (python3.withPackages (
              ps: with ps; [
                west
                pyelftools
                pyyaml
                pykwalify
                packaging
                intelhex
                anytree
                jinja2
                protobuf
                # ZMK v0.3's nanopb generator still imports pkg_resources.
                setuptools_80
              ]
            ))
          ];
        };
    };
}
