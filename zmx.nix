{ lib
, stdenvNoCC
, fetchurl
, installShellFiles
}:

# zmx — terminal session persistence (attach/detach), a focused tmux/screen
# alternative. Not in nixpkgs, so we package the upstream release ourselves.
#
# Upstream ships a prebuilt, *fully static* Zig binary (no ELF interpreter, no
# NEEDED libraries — libghostty-vt is linked in), so it runs on NixOS as-is:
# no autoPatchelfHook, no LD_LIBRARY_PATH wrapping. Building from source would
# instead require zig 0.15 plus vendoring its fetched deps into the sandbox,
# which is far more fragile — hence the binary release.
#
# Bump: change `version`, then update `hash` (a failed build prints the
# correct sha256-… SRI). Pinned here rather than as a flake input because a
# versioned URL + hash needs no flake.lock entry.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "zmx";
  version = "0.6.0";

  src = fetchurl {
    url = "https://github.com/neurosnap/zmx/releases/download/v${finalAttrs.version}/zmx-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-MJ2RO5gq4W6sKoVPQR3kDszAtkr+2JKqAqC+NR8CccE=";
  };

  # The tarball is a single `zmx` file with no top-level directory.
  sourceRoot = ".";

  nativeBuildInputs = [ installShellFiles ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 zmx "$out/bin/zmx"
    runHook postInstall
  '';

  # The binary is native x86_64 and self-contained, so it runs in the sandbox
  # to emit its own completions.
  postInstall = ''
    installShellCompletion --cmd zmx \
      --bash <("$out/bin/zmx" completions bash) \
      --zsh  <("$out/bin/zmx" completions zsh) \
      --fish <("$out/bin/zmx" completions fish)
  '';

  meta = {
    description = "Session attach/detach persistence for terminal processes";
    homepage = "https://zmx.sh";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "zmx";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
