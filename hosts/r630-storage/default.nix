{ config, lib, pkgs, ... }:

{
  imports = [
    ./disko.nix
  ];

  # Keep parity with your installed host boot setup.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Hardware profile for the Dell R630 (moved here so this host is fully
  # declarative and not tied to a generated hardware file with transient UUIDs).
  boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" "nvme" "mpt3sas" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # This host is pre-existing NixOS 25.11; keep its stateVersion unchanged.
  system.stateVersion = lib.mkForce "25.11";

  # ZFS pools used by OpenEBS LocalPV StorageClasses.
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "deadbeef";
  networking.firewall.allowedTCPPorts = lib.mkAfter [ 80 443 ];
  # Match the intended LAN NIC by stable hardware MAC, not interface name.
  systemd.network.networks."10-lan".matchConfig = lib.mkForce {
    PermanentMACAddress = "b0:83:fe:e1:68:6a";
  };
  # This host may not use disko's by-partlabel ESP path yet; don't drop into
  # emergency mode just because /boot is temporarily unavailable.
  fileSystems."/boot".options = lib.mkAfter [
    "nofail"
    "x-systemd.device-timeout=10s"
  ];
  # Keep mount units present for switch logic, but make dataset availability
  # non-fatal and mount lazily.
  fileSystems."/var/lib/zfs-pv/reliable".options = lib.mkAfter [
    "x-systemd.automount"
    "nofail"
    "x-systemd.device-timeout=10s"
    "x-systemd.mount-timeout=10s"
  ];
  fileSystems."/var/lib/zfs-pv/bulk".options = lib.mkAfter [
    "x-systemd.automount"
    "nofail"
    "x-systemd.device-timeout=10s"
    "x-systemd.mount-timeout=10s"
  ];
  boot.zfs.extraPools = [ "r630-main" "r630-bulk" ];
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  # Day-2 safety: ensure expected ZFS datasets exist on already-installed hosts
  # (disko declarations are not applied by regular `nixos-rebuild switch`).
  systemd.services.k8nix-zfs-pv-datasets = {
    description = "Ensure ZFS datasets for k3s PV mountpoints exist";
    after = [ "zfs-import-r630-main.service" "zfs-import-r630-bulk.service" ];
    requires = [ "zfs-import-r630-main.service" "zfs-import-r630-bulk.service" ];
    before = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.zfs pkgs.coreutils ];
    script = ''
      set -eu

      if ! zfs list -H -o name r630-main/k3s/pv >/dev/null 2>&1; then
        zfs create -p \
          -o mountpoint=/var/lib/zfs-pv/reliable \
          -o canmount=on \
          -o recordsize=16K \
          r630-main/k3s/pv
      fi

      if ! zfs list -H -o name r630-bulk/k3s/pv >/dev/null 2>&1; then
        zfs create -p \
          -o mountpoint=/var/lib/zfs-pv/bulk \
          -o canmount=on \
          -o recordsize=1M \
          r630-bulk/k3s/pv
      fi

      mkdir -p /var/lib/zfs-pv/reliable /var/lib/zfs-pv/bulk

      if [ "$(zfs get -H -o value mounted r630-main/k3s/pv)" != "yes" ]; then
        zfs mount r630-main/k3s/pv
      fi

      if [ "$(zfs get -H -o value mounted r630-bulk/k3s/pv)" != "yes" ]; then
        zfs mount r630-bulk/k3s/pv
      fi

      mkdir -p /var/lib/zfs-pv/reliable/gitlab
    '';
  };

  # Ensure the agent starts after storage pools are imported.
  systemd.services.k3s = {
    after = [
      "zfs-import-r630-main.service"
      "zfs-import-r630-bulk.service"
      "k8nix-zfs-pv-datasets.service"
    ];
    requires = [
      "zfs-import-r630-main.service"
      "zfs-import-r630-bulk.service"
      "k8nix-zfs-pv-datasets.service"
    ];
  };

  # Useful scheduling labels for storage/heavy workloads.
  services.k3s.extraFlags = lib.concatStringsSep " " [
    "--node-label=k8nix.io/role=storage"
    "--node-label=k8nix.io/storage=true"
    "--node-label=k8nix.io/ai-data=true"
    "--node-label=workload=heavy"
  ];
}
