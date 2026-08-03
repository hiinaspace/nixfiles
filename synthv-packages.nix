{ pkgs }:

let
  # yabridge 5.1.1 requires Wine <= 9.21. This upstream development branch
  # uses the replacement editor embedding needed by newer Wine releases.
  wine = pkgs.wineWow64Packages.staging;
  winePackages = pkgs.wineWow64Packages // { yabridge = wine; };
  wineLoader = pkgs.writeShellScript "synthv-yabridge-wine" ''
    export WINEDLLOVERRIDES="cryptbase=b''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
    exec ${wine}/bin/wine "$@"
  '';

  yabridge = (pkgs.yabridge.override {
    wineWow64Packages = winePackages;
  }).overrideAttrs (old: {
    version = "5.1.1-unstable-2025-11-16";
    src = pkgs.fetchFromGitHub {
      owner = "robbert-vdh";
      repo = "yabridge";
      rev = "ba7022df0aee1e91cde62d7f0e940d3bc43a82b0";
      hash = "sha256-0ju/mfmhutuuPezq1GhiAEiQV/gnfEbrhjX4ydxLX+A=";
    };
    # The development branch already removed the obsolete 32-bit Winelib
    # targets, so nixpkgs' release-specific patch is both unnecessary and no
    # longer applies. Keep the Nix dependency and profile lookup patches.
    patches = builtins.filter
      (patch: baseNameOf (toString patch) != "libyabridge-drop-32-bit-support.patch")
      old.patches;
    postFixup = (old.postFixup or "") + ''
      substituteInPlace "$out/bin/yabridge-host.exe" \
        --replace-fail '${wine}/bin/wine' '${wineLoader}'
    '';
  });

  yabridgectl = pkgs.yabridgectl.override {
    inherit yabridge;
    wineWow64Packages = winePackages;
  };
in
{
  inherit wine yabridge yabridgectl;
}
