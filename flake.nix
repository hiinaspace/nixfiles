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
    monado-local.url = "path:/home/s/lib/monado";

    # https://github.com/mic92/sops-nix
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-xr, comfyui-nix, monado-local, sops-nix }: {
    nixosConfigurations = {
      sayu = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
	    nixpkgs.overlays = [ comfyui-nix.overlays.default ];
	    #environment.systemPackages = [ nixpkgs.comfy-ui-cuda ];
          }
          ({ ... }: {
            services.monado.package = monado-local.packages.x86_64-linux.default;
          })
          nixpkgs-xr.nixosModules.nixpkgs-xr
          comfyui-nix.nixosModules.default
          ./configuration.nix
          sops-nix.nixosModules.sops
        ];
      };
    };
  };
}
