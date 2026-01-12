{
  description = "Soft-Serve running inside a Firecracker MicroVM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    microvm.url = "github:microvm-nix/microvm.nix";
  };

  outputs = { self, nixpkgs, microvm }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      nixosConfigurations.soft-serve-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          ({ config, pkgs, ... }: {
            networking.hostName = "soft-serve";
            documentation.enable = false;

            users.users.softserve = {
              isNormalUser = true;
              home = "/var/lib/soft-serve";
            };

            environment.systemPackages = [ pkgs.soft-serve ];

            systemd.services.soft-serve = {
              description = "Soft Serve Git Server";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.soft-serve}/bin/soft serve";
                User = "softserve";
                WorkingDirectory = "/var/lib/soft-serve";
                Restart = "always";
              };
            };

            systemd.tmpfiles.rules = [
              "d /var/lib/soft-serve 0755 softserve softserve -"
            ];

            microvm = {
              hypervisor = "firecracker";
              vcpu = 2;
              mem = 1024;
              interfaces = [{
                type = "tap";
                id = "vm-net";
                mac = "02:00:00:00:00:01";
              }];
              shares = [{
                source = "/nix/store";
                mountPoint = "/nix/store";
                tag = "store";
                proto = "virtiofs";
              }];
            };

            networking.useDHCP = true;
            system.stateVersion = "24.05";
          })
        ];
      };

      # Define 'default' so 'nix run' knows what to execute
      packages.${system} = {
        default = self.nixosConfigurations.soft-serve-vm.config.microvm.runner;
      };
    };
}
