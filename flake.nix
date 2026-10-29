{
  description = "Wired PCVR on NixOS: Monado + SteamVR lighthouse, Bigscreen Beyond 2 on NVIDIA, xrizer/Proton, WiVRn";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # https://github.com/nix-community/nixpkgs-xr: xrizer, wayvr, proton-rtsp-bin, lighthouse-steamvr, ...
    nixpkgs-xr.url = "github:nix-community/nixpkgs-xr";
    # Source for the NVENC/CUDA WiVRn build in ./wivrn-local.nix.
    wivrn-src = {
      url = "github:WiVRn/WiVRn/3e73d98ae22cfdc2cdd6a3a0db7e41a958bba936";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs-xr, wivrn-src }:
    let
      system = "x86_64-linux";
    in {
      # Plain modules, not option sets: each one is the author's machine config
      # as it runs. Machine-specific values (user `s`, uid 1000, DP-4,
      # wayland-1, Steam paths under /home/s) are left in place and commented;
      # adapt them in a copy or override them with lib.mkForce.
      # All of them expect nixpkgs-xr's module (or overlay) for its packages.
      nixosModules = {
        monado = ./vr.nix;              # Monado + SteamVR lighthouse driver, BSB2 udev, pressure-vessel env
        bsb2-nvidia = ./nvidia.nix;     # NVIDIA open driver pin + BSB2 DSC patch + suspend/resume units
        steam = ./steam.nix;            # Steam, ntsync, proton-rtsp and GE-Proton builds
        steamvr-native = ./steamvr-native.nix; # native SteamVR session units (needs home-manager)
        default = {
          imports = [
            nixpkgs-xr.nixosModules.nixpkgs-xr
            self.nixosModules.monado
            self.nixosModules.bsb2-nvidia
            self.nixosModules.steam
          ];
        };
      };

      # start-vr/stop-vr, vr-session target, base-station power, xrizer
      # openvrpaths and VRChat bindings.
      homeManagerModules.vr-session = ./home-vr.nix;

      # pkgs.wivrn-frame: WiVRn with NVENC and its patched Monado revision.
      overlays.wivrn-frame = final: prev: {
        wivrn-frame = final.callPackage ./wivrn-local.nix { src = wivrn-src; };
      };

      # Evaluation smoke test for `nix flake check`; not a bootable machine.
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          {
            nixpkgs.config.allowUnfree = true;
            boot.loader.grub.devices = [ "nodev" ];
            fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
            system.stateVersion = "26.05";
          }
        ];
      };

      packages.${system}.wivrn-frame =
        (import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ nixpkgs-xr.overlays.default self.overlays.wivrn-frame ];
        }).wivrn-frame;

      devShells.${system}.default =
        let pkgs = nixpkgs.legacyPackages.${system};
        in pkgs.mkShell { packages = with pkgs; [ git gitleaks pre-commit ]; };
    };
}
