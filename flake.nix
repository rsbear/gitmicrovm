{
  description = "Firecracker-based Git Server for multi-tenant platform";
  
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
            networking.hostName = "git-server";
            
            # Minimal system - no docs, no extra packages
            documentation.enable = false;
            environment.noXlibs = true;
            
            users.users.git = {
              isNormalUser = true;
              home = "/var/lib/git";
              description = "Git user";
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
                # Bind to all interfaces
                Environment = [
                  "SOFT_SERVE_BIND_ADDRESS=:23231"
                  "SOFT_SERVE_SSH_LISTEN_ADDR=:23232"
                ];
              };
            };
            
            systemd.tmpfiles.rules = [
              "d /var/lib/git 0755 git git -"
            ];
            
            microvm = {
              hypervisor = "firecracker";
              
              # Minimal resources per VM
              vcpu = 1;
              mem = 512;  # 512MB should be plenty for a git server
              
              # Network interface for the VM
              interfaces = [{
                type = "tap";
                id = "vm-${config.networking.hostName}";
                mac = "02:00:00:00:00:01";  # You'd generate this dynamically
              }];
              
              # NO SHARES - everything baked into the image
              shares = [];
              
              # Persistent volume for git repositories
              volumes = [{
                image = "git-data.img";
                mountPoint = "/var/lib/git";
                size = 2048;  # 2GB for repos
              }];
              
              # Firecracker-specific optimizations
              kernel.enable = true;
              initrd.enable = true;
            };
            
            # Minimal networking
            networking.useDHCP = true;
            networking.firewall = {
              enable = true;
              allowedTCPPorts = [ 23231 23232 ];  # HTTP and SSH
            };
            
            # Minimal boot
            boot.isContainer = false;
            boot.initrd.systemd.enable = false;
            
            system.stateVersion = "24.05";
          })
        ];
      };
    in
    {
      nixosConfigurations.git-server = vmConfig;
      
      packages.${system} = {
        # The kernel and initrd for Firecracker
        kernel = vmConfig.config.microvm.kernel.file;
        initrd = vmConfig.config.microvm.initrd.file;
        
        # The root filesystem image
        rootfs = vmConfig.config.microvm.rootfs;
        
        # The runner script
        default = vmConfig.config.microvm.declaredRunner;
        vm = vmConfig.config.microvm.declaredRunner;
      };
      
      apps.${system}.default = {
        type = "app";
        program = "${vmConfig.config.microvm.declaredRunner}/bin/microvm-run";
      };
    };
}
