{
  description = "QEMU-based Git Server for Hetzner CPX VPS";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    microvm.url = "github:microvm-nix/microvm.nix";
  };
  
  outputs = { self, nixpkgs, microvm }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      
      vmConfig = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          ({ config, pkgs, ... }: {
            networking.hostName = "git-server";
            
            documentation.enable = false;
            
            users.users.git = {
              isNormalUser = true;
              home = "/var/lib/git";
            };
            
            environment.systemPackages = [ pkgs.soft-serve ];
            
            systemd.services.soft-serve = {
              description = "Soft Serve Git Server";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.soft-serve}/bin/soft serve";
                User = "git";
                WorkingDirectory = "/var/lib/git";
                Restart = "always";
              };
            };
            
            systemd.tmpfiles.rules = [
              "d /var/lib/git 0755 git git -"
            ];
            
            microvm = {
              hypervisor = "qemu";
              vcpu = 2;
              mem = 1024;
              
              # User-mode networking (no root/TAP setup needed)
              interfaces = [{
                type = "user";
                id = "vm-net";
                mac = "02:00:00:00:00:01";
              }];
              
              # No shares - self-contained VM
              shares = [];
              
              # Persistent volume for git repos
              volumes = [{
                image = "git-data.img";
                mountPoint = "/var/lib/git";
                size = 2048;
              }];
              
              # Socket for serial console
              socket = "git-server.sock";
            };
            
            networking.firewall = {
              enable = true;
              allowedTCPPorts = [ 23231 23232 ];
            };
            
            system.stateVersion = "24.05";
          })
        ];
      };
    in
    {
      nixosConfigurations.git-server = vmConfig;
      
      packages.${system}.default = vmConfig.config.microvm.declaredRunner;
      
      apps.${system}.default = {
        type = "app";
        program = "${vmConfig.config.microvm.declaredRunner}/bin/microvm-run";
      };
    };
}
