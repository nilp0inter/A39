{
  description = "Una distribución de Linux para operar con la administración pública española";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
  inputs.home-manager.url = "github:nix-community/home-manager/release-23.05";
  inputs.autofirma-nix.url = "github:nilp0inter/autofirma-nix";
  outputs = { self, nixpkgs, home-manager, autofirma-nix }@inputs: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    lib = nixpkgs.lib;
  in {
    nixosConfigurations = {
      A39 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # Modules for installed systems only.
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-base.nix"
          home-manager.nixosModules.home-manager
          ({ config, ... }: {
            isoImage.isoName = lib.mkForce "A39.iso";
            isoImage.appendToMenuLabel = " A39 System ";

            isoImage.squashfsCompression = "gzip -Xcompression-level 1";
            # EFI booting
            isoImage.makeEfiBootable = true;

            # USB booting
            isoImage.makeUsbBootable = true;

            time.timeZone = "Europe/Madrid";
            time.hardwareClockInLocalTime = true;

            # Needed by yubikey tools
            services.pcscd.enable = true;

            networking.hostName = "A39";

            services.cinnamon.apps.enable = false;
            services.xserver.desktopManager.cinnamon.enable = true;
            services.xserver.displayManager.autoLogin.enable = true;
            services.xserver.displayManager.autoLogin.user = "nixos";

            networking.firewall.allowedTCPPorts = [ 9501 ];

            environment.variables.JAVAX_NET_SSL_TRUSTSTORE =
              let
                caBundle = config.environment.etc."ssl/certs/ca-bundle.crt".source;
                p11kit = pkgs.p11-kit.overrideAttrs (oldAttrs: {
                  configureFlags = [
                    "--with-trust-paths=${caBundle}"
                  ];
                });
              in
              derivation {
                name = "java-cacerts";
                builder = pkgs.writeShellScript "java-cacerts-builder" ''
                  ${p11kit.bin}/bin/trust \
                    extract \
                    --format=java-cacerts \
                    --purpose=server-auth \
                    $out
                '';
                system = "x86_64-linux";
              };

            system.stateVersion = "23.05";
          })
          ({ ... }: {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.nixos = {
              imports = [
                autofirma-nix.homeManagerModules.default
                ({ config, pkgs, lib, ... }: {
                  home.packages = with pkgs; [
                    android-tools
                  ];

                  home.file."dnieRemote.cfg".text = ''
                  jumpintro=0;
                  wifiport=9501;
                  '';

                  programs.autofirma.enable = true;
                  programs.autofirma.firefoxIntegration.profiles.default.enable = true;

                  programs.dnieremote.enable = true;

                  programs.configuradorfnmt.enable = true;
                  programs.configuradorfnmt.firefoxIntegration.profiles.default.enable = true;

                  home.activation.autofirma = lib.hm.dag.entryAfter ["writeBoundary"] ''
                    $DRY_RUN_CMD ${config.programs.autofirma.finalPackage}/bin/autofirma-setup
                  '';

                  programs.firefox = {
                    enable = true;
                    package = pkgs.firefox.override (args: {
                      extraPolicies = {
                        AppAutoUpdate = false;
                        BackgroundAppUpdate = false;
                        DisableAppUpdate = true;
                        DisableFeedbackCommands = true;
                        DisableFirefoxStudies = true;
                        DisableProfileImport = true;
                        DisableSystemAddonUpdate = true;
                        DisableTelemetry = true;
                        DontCheckDefaultBrowser = true;
                        NoDefaultBookmarks = true;
                        OfferToSaveLogins = false;
                        OverrideFirstRunPage = "";
                        OverridePostUpdatePage = "";
                        PasswordManagerEnabled = false;

                        SecurityDevices = {
                          "OpenSC PKCS11" = "${pkgs.opensc}/lib/opensc-pkcs11.so";  # Para poder utilizar el DNIe, y otras tarjetas inteligentes
                          "DNIeRemote" = "${config.programs.dnieremote.finalPackage}/lib/libdnieremotepkcs11.so";  # Para poder utilizar el DNIe por NFC desde un móvil Android
                        };
                      };
                    });
                    profiles.default = {
                      id = 0;  # Hace que este perfil sea el perfil por defecto
                      # ... El resto de opciones de configuración de este perfil
                    };
                  };
                })
              ];
              home.stateVersion = "23.05";
            };
          })
        ];
      };
    };

    packages.x86_64-linux.default = self.nixosConfigurations.A39.config.system.build.isoImage;

    apps.x86_64-linux.default = let
      launch-iso = pkgs.writeScriptBin "launch-iso" ''
        [ ! -f /tmp/A39.drive ] && dd if=/dev/zero of=/tmp/A39.drive bs=1M count=64
        ${pkgs.qemu}/bin/qemu-system-x86_64 -device qemu-xhci,id=xhci -device usb-host,bus=xhci.0,vendorid=0x0403,productid=0x6015 -enable-kvm -m 2048 -cdrom ${self.nixosConfigurations.A39.config.system.build.isoImage}/iso/A39.iso -hda /tmp/A39.drive
      '';
    in {
      type = "app";
      program = "${launch-iso}/bin/launch-iso";
    };
  };
}
