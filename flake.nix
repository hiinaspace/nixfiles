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
    wivrn-src = {
      url = "github:WiVRn/WiVRn/3e73d98ae22cfdc2cdd6a3a0db7e41a958bba936";
      flake = false;
    };
    comfyui-nix.url = "github:utensils/comfyui-nix";

    # Source-only input: pinned in flake.lock, packaged locally in ./pikeru.nix.
    # Bump with `nix flake update pikeru-src`.
    pikeru-src = {
      url = "github:dvhar/pikeru";
      flake = false;
    };

    # https://github.com/sadjow/codex-cli-nix
    codex-cli-nix.url = "github:sadjow/codex-cli-nix";
    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";

    # https://github.com/sadjow/claude-code-nix
    # Claude Code CLI, tracking Anthropic's native releases (updated hourly).
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # https://github.com/danielbodart/claude-desktop
    # Official Claude Desktop .deb from Anthropic's signed apt repo
    # (downloads.claude.ai), hash-pinned. Built locally; the flake's cachix
    # substituter is deliberately not trusted. Bump: nix flake update claude-desktop
    claude-desktop = {
      url = "github:danielbodart/claude-desktop";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Source-only input: pinned in flake.lock, packaged locally in ./animutools.nix.
    # Local edits to the checkout in ~/code/animutools are NOT picked up here —
    # push to github, then `nix flake update animutools-src` + rebuild.
    animutools-src = {
      url = "github:hiinaspace/animutools";
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

  outputs = inputs @ { self, nixpkgs, nixpkgs-xr, wivrn-src, comfyui-nix, pikeru-src, animutools-src, home-manager, sops-nix, impermanence, codex-cli-nix, codex-desktop-linux, claude-code-nix, claude-desktop }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      patchedMonado = nixpkgs-xr.packages.${system}.monado.overrideAttrs (old: {
        patches = (old.patches or []) ++ [
          ./monado-steamvr-lh-reinit.patch
        ];
      });
      patchedXrizer = nixpkgs-xr.packages.${system}.xrizer.overrideAttrs (old: {
        patches = (old.patches or []) ++ [
          ./xrizer-skyrimvr-monado.patch
          ./xrizer-standard-pose-components.patch
          ./xrizer-vulkan-device-lost-cleanup.patch
        ];
      });
      wivrnOverlay = final: prev: {
        wivrn-frame = final.callPackage ./wivrn-local.nix { src = wivrn-src; };
      };
      xrizerPatchOverlay = final: prev: {
        xrizer = patchedXrizer;
      };
      # Overlay exposing our locally-packaged pikeru as pkgs.pikeru.
      pikeruOverlay = final: prev: {
        pikeru = final.callPackage ./pikeru.nix { src = pikeru-src; };
      };
      # Overlay exposing animutools (fenc) as pkgs.animutools.
      animutoolsOverlay = final: prev: {
        animutools = final.python3Packages.callPackage ./animutools.nix { src = animutools-src; };
      };
    in {
    nixosConfigurations = {
      sayu = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
	    nixpkgs.overlays = [ comfyui-nix.overlays.default pikeruOverlay animutoolsOverlay xrizerPatchOverlay wivrnOverlay ];
          }
          ({ ... }: {
            services.monado.package = patchedMonado;
          })
          nixpkgs-xr.nixosModules.nixpkgs-xr
          claude-desktop.nixosModules.default
          ({ ... }: {
            # Claude Desktop (chat, Code tab, Remote Control) plus the claude CLI
            # on the system PATH, so SSH sessions from other hosts find it too.
            programs.claude-desktop.enable = true;
            environment.systemPackages = [ claude-code-nix.packages.${system}.default ];
          })
          comfyui-nix.nixosModules.default
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

	    home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.s = import ./home.nix;
          }
        ];
      };
    };

    packages.${system}.wivrn-frame = self.nixosConfigurations.sayu.pkgs.wivrn-frame;
    devShells.${system} = {
      wivrn = self.nixosConfigurations.sayu.pkgs.wivrn-frame;
      default =
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in pkgs.mkShell {
          buildInputs = [
            codex-cli-nix.packages.${system}.default
          ];
          packages = with pkgs; [
            git
            gitleaks
            pre-commit
          ];
        };
    };
  };
}
