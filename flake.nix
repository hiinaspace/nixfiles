# /etc/nixos/flake.nix
{
  description = "flake for sayu";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
    # more up to date VR stuff
    # https://github.com/nix-community/nixpkgs-xr
    nixpkgs-xr.url = "github:nix-community/nixpkgs-xr";
    comfyui-nix.url = "github:utensils/comfyui-nix";
    clipboard-sync.url = "github:dnut/clipboard-sync";

    # Source-only input: pinned in flake.lock, packaged locally in ./pikeru.nix.
    # Bump with `nix flake update pikeru-src`.
    pikeru-src = {
      url = "github:dvhar/pikeru";
      flake = false;
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # https://github.com/mic92/sops-nix
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Ephemeral-root persistence. Pinned now; wired in at the impermanence reinstall
    # (see ./impermanence.nix). Inert until then.
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs = { self, nixpkgs, nixpkgs-xr, comfyui-nix, clipboard-sync, pikeru-src, home-manager, sops-nix, impermanence }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      patchedMonado = nixpkgs-xr.packages.${system}.monado.overrideAttrs (old: {
        patches = (old.patches or []) ++ [
          ./monado-steamvr-lh-reinit.patch
        ];
      });
      # Overlay exposing our locally-packaged pikeru as pkgs.pikeru.
      pikeruOverlay = final: prev: {
        pikeru = final.callPackage ./pikeru.nix { src = pikeru-src; };
      };
    in {
    nixosConfigurations = {
      sayu = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
	    nixpkgs.overlays = [ comfyui-nix.overlays.default pikeruOverlay ];
          }
          ({ ... }: {
            services.monado.package = patchedMonado;
          })
          nixpkgs-xr.nixosModules.nixpkgs-xr
          comfyui-nix.nixosModules.default
          clipboard-sync.nixosModules.default
          ./configuration.nix
          sops-nix.nixosModules.sops
          # Impermanence: ephemeral root, rolled back to @blank each boot. Active
          # since the btrfs reinstall (see ./impermanence.nix).
          impermanence.nixosModules.impermanence
          ./impermanence.nix
          home-manager.nixosModules.home-manager
          {
            # Home Manager as a NixOS module: one `nixos-rebuild switch` builds and
            # activates both system and home, sharing the system's pkgs + overlays.
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Safety net for the standalone->module transition: back up any colliding
            # file instead of aborting activation.
            home-manager.backupFileExtension = "hm-bak";
            home-manager.users.s = import ./home.nix;
          }
        ];
      };
    };

    devShells.${system}.default =
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in pkgs.mkShell {
        packages = with pkgs; [
          git
          gitleaks
          pre-commit
        ];
      };
  };
}
