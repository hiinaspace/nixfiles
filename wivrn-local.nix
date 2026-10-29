# Adapt the upstream WiVRn flake / nixpkgs recipe for the Frame experiment.
# Override wivrn-src with path:/home/s/code/wivrn to build local modifications.
{ lib, wivrn, applyPatches, fetchFromGitLab, libpng, util-linux, src }:
let
  source = lib.cleanSourceWith {
    inherit src;
    filter = name: type:
      let base = baseNameOf name; in
      lib.cleanSourceFilter name type
      && !(lib.hasPrefix "build" base && type == "directory")
      && !(lib.hasPrefix "result" base);
  };
in (wivrn.override { cudaSupport = true; }).overrideAttrs (final: old: {
  pname = "wivrn-frame";
  version = "26.9-frame-3e73d98";
  src = source;
  postUnpack = null;
  monado = applyPatches {
    src = fetchFromGitLab {
      domain = "gitlab.freedesktop.org";
      owner = "monado";
      repo = "monado";
      rev = lib.strings.trim (builtins.readFile (src + "/monado-rev"));
      hash = "sha256-3+bdxyXHuaweT/K+Jwh428XNMuZUd1tL2bdFBRIZ/Po=";
    };
    postPatch = ''${source}/patches/apply.sh ${source}/patches/monado/*'';
  };
  buildInputs = old.buildInputs ++ [ libpng ];
  nativeBuildInputs = old.nativeBuildInputs ++ [ util-linux ];
  cmakeFlags = (lib.filter (flag:
    !(lib.hasPrefix "-DGIT_" flag || lib.hasPrefix "-DFETCHCONTENT_SOURCE_DIR_MONADO" flag)
  ) old.cmakeFlags) ++ [
    "-DGIT_DESC=26.9-frame-local"
    "-DGIT_COMMIT=3e73d98ae22cfdc2cdd6a3a0db7e41a958bba936"
    "-DFETCHCONTENT_SOURCE_DIR_MONADO=${final.monado}"
  ];
})
