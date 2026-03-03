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
  # Keep the node reachable if one of the ZFS data pools is unavailable.
  fileSystems."/var/lib/zfs-pv/reliable".options = lib.mkAfter [
    "noauto"
    "nofail"
    "x-systemd.device-timeout=10s"
  ];
  fileSystems."/var/lib/zfs-pv/bulk".options = lib.mkAfter [
    "noauto"
    "nofail"
    "x-systemd.device-timeout=10s"
  ];
  boot.zfs.extraPools = [ "r630-main" "r630-bulk" ];
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  # Ensure the agent starts after storage pools are imported.
  systemd.services.k3s = {
    after = [ "zfs-import-r630-main.service" "zfs-import-r630-bulk.service" ];
    requires = [ "zfs-import-r630-main.service" "zfs-import-r630-bulk.service" ];
  };

  # Useful scheduling labels for storage/heavy workloads.
  services.k3s.extraFlags = lib.concatStringsSep " " [
    "--node-label=node-role.kubernetes.io/storage=true"
    "--node-label=workload=heavy"
  ];
}
