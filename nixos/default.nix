{ configuration
, system ? "x86_64-linux"
}:

let
  eval-config = import <nixpkgs/nixos/lib/eval-config.nix>;
  baseModules = [stub-module]
             ++ import <microgram/nixos/vendor-module-list.nix>;

  lib = import <nixpkgs/lib>;

  stub = with lib; mkOption {
    type = types.attrsOf types.unspecified;
    default = {
      enable = false;
      nssmdns = false;
      nsswins = false;
      syncPasswordsByPam = false;
      isContainer = false;
      devices = [];
    };
  };

  stub-module = {
    options = {
      services.xserver = stub;
      services.bind = stub;
      services.dnsmasq = stub;
      services.avahi = stub;
      services.samba = stub;
      services.mstpd = stub;
      services.resolved = stub;
      services.fprintd = stub;
      security.grsecurity = stub;
      services.virtualboxGuest = stub;
      users.ldap = stub;
      krb5 = stub;
      powerManagement = stub;
      security.pam.usb = stub;
      security.pam.mount = stub;
      security.pam.oath = stub;
      boot.isContainer = lib.mkOption { default = false; };
      boot.initrd.luks = stub;
      networking.wireless = stub;
      networking.connman = stub;
      virtualisation.vswitch = stub;
    };
    config = {
      services.virtualboxGuest = true; # renamed
      services.xserver.enable = false;
      powerManagement.enable = false;
      powerManagement.resumeCommands = "";
      powerManagement.powerUpCommands = "";
      powerManagement.powerDownCommands = "";

      nixpkgs.config = (import <microgram/sdk.nix>).nixpkgs-config;
    };
  };

  eval = eval-config {
    inherit system baseModules;
    modules = [ configuration ];
  };
in rec {
  inherit (eval) config options;

  system = eval.config.system.build.toplevel;
}
