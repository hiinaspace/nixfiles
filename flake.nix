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

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # https://github.com/mic92/sops-nix
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-xr, comfyui-nix, home-manager, sops-nix }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      patchedMonado = nixpkgs-xr.packages.${system}.monado.overrideAttrs (old: {
        patches = (old.patches or []) ++ [
          ./monado-steamvr-lh-reinit.patch
        ];
      });
    in {
    nixosConfigurations = {
      sayu = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
	    nixpkgs.overlays = [ comfyui-nix.overlays.default ];
          }
          ({ ... }: {
            services.monado.package = patchedMonado;
          })
          nixpkgs-xr.nixosModules.nixpkgs-xr
          comfyui-nix.nixosModules.default
          ./configuration.nix
          sops-nix.nixosModules.sops
        ];
      };
    };

    homeConfigurations."s" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ nixpkgs-xr.overlays.default ];
      };
      modules = [ ./home.nix ];
    };
  };
}
