{
  description = "NixOS mixed-architecture k3s cluster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    disko.url = "github:nix-community/disko";

    agenix.url = "github:ryantm/agenix";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, disko, agenix, home-manager }:
    let
      # Default platform for Raspberry Pi nodes.
      piSystem = "aarch64-linux";

      # Shell tooling should be available on common dev hosts too.
      devSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs devSystems (system: f system);

      commonModules = [
        agenix.nixosModules.default
        home-manager.nixosModules.home-manager
        ./modules/base.nix
        ./modules/networking.nix
      ];

      piModules = [
        nixos-hardware.nixosModules.raspberry-pi-4
        ./modules/sd-image.nix
      ];

      r630Modules = [
        disko.nixosModules.disko
      ];

      mkHost = { hostName, roleModule, system ? piSystem, extraModules ? [ ] }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit hostName; };

          modules =
            commonModules
            ++ extraModules
            ++ [
              roleModule
              (./hosts + "/${hostName}/default.nix")
            ];
        };
    in
    {
      nixosConfigurations = {
        pi-master-1     = mkHost { hostName = "pi-master-1";     roleModule = ./modules/k3s/server.nix; extraModules = piModules; };
        pi-worker-1     = mkHost { hostName = "pi-worker-1";     roleModule = ./modules/k3s/agent.nix;  extraModules = piModules; };
        pi-worker-2     = mkHost { hostName = "pi-worker-2";     roleModule = ./modules/k3s/agent.nix;  extraModules = piModules; };
        pi-worker-3     = mkHost { hostName = "pi-worker-3";     roleModule = ./modules/k3s/agent.nix;  extraModules = piModules; };
        pi-worker-4     = mkHost { hostName = "pi-worker-4";     roleModule = ./modules/k3s/agent.nix;  extraModules = piModules; };
        r630-storage    = mkHost { hostName = "r630-storage";    roleModule = ./modules/k3s/agent.nix;  system = "x86_64-linux"; extraModules = r630Modules; };
      };

      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          packages = [ agenix.packages.${system}.default ];
        };
      });
    };
}
