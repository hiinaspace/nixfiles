{ pkgs, ... }:
let
  # The previously working GE 10 RTSP build, kept selectable in Steam under a
  # distinct name as a fallback for VRChat's video players.
  protonRtsp10Fallback =
    pkgs.proton-ge-bin.overrideAttrs
      (
        finalAttrs: _: {
          steamDisplayName = "GE-Proton-rtsp-10-fallback";
          pname = "proton-ge-rtsp-bin";
          # Pin the known-good fallback directly: nixpkgs-xr's wrapper still
          # passes steamDisplayName through the removed .override interface.
          version = "GE-Proton10-33-rtsp23-4";
          toolName = finalAttrs.version; # RTSP manifests omit the architecture suffix.
          src = pkgs.fetchzip {
            url = "https://github.com/SpookySkeletons/proton-ge-rtsp/releases/download/${finalAttrs.version}/${finalAttrs.version}.tar.gz";
            hash = "sha256-sP+xNPbeI1jbs081QvFmj48A/yG6IC9ZPZRvGkFZnX0=";
          };
          meta.homepage = "https://github.com/SpookySkeletons/proton-rtsp";
        }
      );

  # Latest GE-Proton, ahead of nixpkgs (11-7 at the time). Carries upstream
  # VRChat AVPro finite-video/livestream fixes newer than proton-rtsp's June
  # Wine base; a general pick for VRChat or other games. Bump: change version,
  # set hash = lib.fakeHash, rebuild, paste the reported hash.
  protonGeLatest =
    pkgs.proton-ge-bin.overrideAttrs
      (
        finalAttrs: _: {
          steamDisplayName = finalAttrs.version;
          version = "GE-Proton11-11";
          src = pkgs.fetchzip {
            url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${finalAttrs.version}/${finalAttrs.version}-x86_64.tar.gz";
            hash = "sha256-3tVgf83IkteFtVo/bHd4yG1xCtPeuW8FXaTrHOLjvKQ=";
          };
        }
      );
in
{
  # Proton 11's wineserver uses /dev/ntsync instead of fsync when present.
  # Works around VRChat's "Fatal Error in GC (SuspendThread Loop failed)"
  # IL2CPP aborts, which hit under fsync on Proton 11 (Oct 2026).
  # https://feedback.vrchat.com/bug-reports/p/fatal-error-in-gc-suspendthread-loop-failed
  boot.kernelModules = [ "ntsync" ];

  programs.steam = {
    enable = true;
    extraCompatPackages = [
      # Current VRChat RTSP/Media Foundation fork (Proton 11), from nixpkgs-xr.
      # https://lvra.gitlab.io/docs/vrchat/video_players/
      pkgs.proton-rtsp-bin
      # Keep the previously working nixpkgs-xr build selectable in Steam.
      protonRtsp10Fallback
      # Latest GE-Proton (shows in Steam as its version, e.g. "GE-Proton11-11").
      protonGeLatest
    ];
  };
}
