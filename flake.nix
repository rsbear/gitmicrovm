{
  description = "Soft-Serve running inside a QEMU MicroVM";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    microvm.url = "github:microvm-nix/microvm.nix";
  };
  
  outputs = { self, nixpkgs, microvm }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      
      # Build the NixOS configuration
      vmConfig = nixpkgs.lib.nixosSystem {
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
              hypervisor = "qemu";
              vcpu = 2;
              mem = 1024;
              interfaces = [{
                type = "tap";
                id = "vm-net";
                mac = "02:00:00:00:00:01";
              }];
              # Use 9p instead of virtiofs for better compatibility
              shares = [{
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                tag = "ro-store";
                proto = "9p";
                securityModel = "none";
              }];
              # Persistent volume for git data
              volumes = [{
                image = "soft-serve-data.img";
                mountPoint = "/var/lib/soft-serve";
                size = 1024;
              }];
              # Ensure writable nix store overlay
              writableStoreOverlay = "/nix/.rw-store";
            };
            
            networking.useDHCP = true;
            networking.firewall.allowedTCPPorts = [ 22 23231 9418 ];
            
            system.stateVersion = "24.05";
          })
        ];
      };
    in
    {
      nixosConfigurations.soft-serve-vm = vmConfig;
      
      packages.${system} = {
        default = vmConfig.config.microvm.declaredRunner;
        vm = vmConfig.config.microvm.declaredRunner;
      };
      
      apps.${system}.default = {
        type = "app";
        program = "${vmConfig.config.microvm.declaredRunner}/bin/microvm-run";
      };
    };
}
