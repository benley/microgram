{ config, lib, ... }: with lib;
let
  inherit (import <microgram/sdk.nix>) sdk pkgs nixpkgs-config;
  systemd-pkg = pkgs.systemd;

  cloudDefault = mkOverride 900;

  fd-limit.soft = "262140";
  fd-limit.hard = "524280";
  core-limit = "1048576"; # one gigabyte
in
{
  imports = [
    ./ntpd.nix
  ];

  nixpkgs.config = nixpkgs-config;

  # usually covered by things like security groups
  networking.firewall.enable = cloudDefault false;

  # likely not needed on a cloud box
  environment.noXlibs = cloudDefault true;

  time.timeZone = cloudDefault "UTC";
  i18n.supportedLocales = cloudDefault ["en_US.UTF-8/UTF-8"];

  services.ntp.enable = true;
  services.ntp.servers = [
    "0.amazon.pool.ntp.org"
    "1.amazon.pool.ntp.org"
    "3.amazon.pool.ntp.org"
  ];

  nix.package = sdk.nix;
  nix.readOnlyStore = true;
  nix.trustedBinaryCaches = [ "http://hydra.nixos.org" ];

  services.openssh.enable = cloudDefault true;
  services.openssh.passwordAuthentication = cloudDefault false;
  services.openssh.challengeResponseAuthentication = cloudDefault false;

  security.pam.loginLimits = [ # login sessions only, not systemd services
    { domain = "*"; type = "hard"; item = "core"; value = core-limit; }
    { domain = "*"; type = "soft"; item = "core"; value = core-limit; }

    { domain = "*"; type = "soft"; item = "nofile"; value = fd-limit.soft; }
    { domain = "*"; type = "hard"; item = "nofile"; value = fd-limit.hard; }
  ];

  systemd.extraConfig = ''
    DefaultLimitCORE=${core-limit}
    DefaultLimitNOFILE=${fd-limit.soft}
  '';

  environment.etc."systemd/coredump.conf".text = ''
    [Coredump]
    Storage=journal
  '';

  # Don't start a tty on the serial consoles.
  #systemd.services."serial-getty@ttyS0".enable = false;
  #systemd.services."serial-getty@hvc0".enable = false;
  #systemd.services."getty@tty1".enable = false;
  #systemd.services."autovt@".enable = false;

  boot.kernelParams = [ "panic=1" "boot.panic_on_fail" ];

  boot.tmpOnTmpfs = cloudDefault false;
  boot.cleanTmpDir = cloudDefault true;
  boot.vesa = false;

  environment.systemPackages = [
    config.boot.kernelPackages.sysdig
    config.boot.kernelPackages.perf
  ];
  boot.extraModulePackages = [ config.boot.kernelPackages.sysdig ];
  boot.kernelModules = [ "sysdig-probe" ];

  boot.kernel.sysctl = {
    # allows control of core dumps with systemd-coredumpctl
    "kernel.core_pattern" = cloudDefault "|${systemd-pkg}/lib/systemd/systemd-coredump %p %u %g %s %t %e";

    "fs.file-max" = cloudDefault fd-limit.hard;

    # moar ports
    "net.ipv4.ip_local_port_range" = cloudDefault "10000 65535";

    # should be the default, really
    "net.ipv4.tcp_slow_start_after_idle" = cloudDefault "0";
    "net.ipv4.tcp_early_retrans" = cloudDefault "1"; # 3.5+

    # backlogs
    "net.core.netdev_max_backlog" = cloudDefault "4096";
    "net.core.somaxconn" = cloudDefault "4096";

    # tcp receive flow steering (newer kernels)
    "net.core.rps_sock_flow_entries" = cloudDefault "32768";

    # max bounds for buffer autoscaling (16 megs for 10 gbe)
    #"net.core.rmem_max" = cloudDefault "16777216";
    #"net.core.wmem_max" = cloudDefault "16777216";
    #"net.core.optmem_max" = cloudDefault "40960";
    #"net.ipv4.tcp_rmem" = cloudDefault "4096 87380 16777216";
    #"net.ipv4.tcp_wmem" = cloudDefault "4096 65536 16777216";

    "net.ipv4.tcp_max_syn_backlog" = cloudDefault "8096";

    # read http://vincent.bernat.im/en/blog/2014-tcp-time-wait-state-linux.html
    "net.ipv4.tcp_tw_reuse" = cloudDefault "1";

    # vm
    #"vm.overcommit_memory" = lib.mkDefault "2"; # no overcommit
    #"vm.overcommit_ratio" = "100";
    "vm.swappiness" = cloudDefault "10"; # discourage swap

    # just in case for postgres and friends
    "kernel.msgmnb" = cloudDefault "65536";
    "kernel.msgmax" = cloudDefault "65536";
    "kernel.shmmax" = cloudDefault "68719476736";
  };
}
