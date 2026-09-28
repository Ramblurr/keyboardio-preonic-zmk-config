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
                mkdir -p "$PRJ_ROOT/out/zmk/config"
                cp "$PRJ_ROOT/config/west.yml" "$PRJ_ROOT/out/zmk/config/west.yml"
                cd "$PRJ_ROOT/out/zmk"
                if [[ ! -d .west ]]; then
                  west init -l config
                fi
                west update
              '';
            }
            {
              name = "zmk-build";
              help = "Build firmware: zmk-build [qwerty|colemak-dhm] [west build options]";
              command = ''
                set -euo pipefail
                layout=qwerty
                case "''${1:-}" in
                  qwerty|colemak-dhm) layout="$1"; shift ;;
                  ""|-*) ;;
                  *) echo "Unknown layout: $1 (use qwerty or colemak-dhm)" >&2; exit 2 ;;
                esac
                if [[ ! -d "$PRJ_ROOT/out/zmk/.west" ]]; then
                  echo "ZMK workspace is not initialized. Run zmk-init first, then retry zmk-build." >&2
                  exit 1
                fi
                cd "$PRJ_ROOT/out/zmk"
                # Avoid west's wrapper prepending a Python without our build modules.
                python3 -m west build -s zmk/app -d "build/$layout" \
                  -S studio-rpc-usb-uart \
                  -b keyboardio_preonic -p auto "$@" -- \
                  -DZephyr_DIR="$PRJ_ROOT/out/zmk/zephyr/share/zephyr-package/cmake" \
                  -DZMK_CONFIG="$PRJ_ROOT/config" \
                  -DKEYMAP_FILE="$PRJ_ROOT/config/$layout.keymap" \
                  -DZMK_EXTRA_MODULES="$PRJ_ROOT" \
                  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
              '';
            }
            {
              name = "zmk-keymap";
              help = "Export QWERTY and Colemak-DHm keymaps to out/ as SVG, PNG and PDF";
              command =
                let
                  drawerConfig = pkgs.writeText "preonic-keymap-drawer.yaml" ''
                    draw_config:
                      footer_text: "Host layout: US | Rotary encoder: volume | Triangle: inherit lower layer | Pink: held layer key"
                    parse_config:
                      raw_binding_map:
                        "&bootloader": "Bootloader"
                        "&studio_unlock": "Unlock Studio"
                        "&sw_bt1": {t: BT, h: "0 / Green"}
                        "&sw_bt2": {t: BT, h: "1 / Red"}
                        "&sw_bt3": {t: BT, h: "2 / Magenta"}
                        "&sw_bt4": {t: BT, h: "3 / Violet"}
                        "&sw_bt5": {t: BT, h: "4 / Yellow"}
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
                  layout=out/zmk/keyboardio-preonic-zmk-module/boards/arm/keyboardio_preonic/keyboardio_preonic-layouts.dtsi
                  if [[ ! -f "$layout" ]]; then
                    echo "Missing Preonic layout: run zmk-init first." >&2
                    exit 1
                  fi
                  mkdir -p out
                  for keymap in qwerty colemak-dhm; do
                    ${pkgs.keymap-drawer}/bin/keymap -c ${drawerConfig} parse \
                      -z "config/$keymap.keymap" -o "out/$keymap.yaml"
                    ${pkgs.keymap-drawer}/bin/keymap -c ${drawerConfig} draw \
                      "out/$keymap.yaml" -d "$layout" -l mit_layout -o "out/$keymap.svg"
                    ${pkgs.inkscape}/bin/inkscape "out/$keymap.svg" \
                      --export-type=png --export-filename="out/$keymap.png" \
                      --export-dpi=192 --export-background=white --export-background-opacity=1
                    ${pkgs.inkscape}/bin/inkscape "out/$keymap.svg" \
                      --export-type=pdf --export-filename="out/$keymap.pdf"
                    printf 'Exported %s/out/%s.{svg,png,pdf}\n' "$PRJ_ROOT" "$keymap"
                  done
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
