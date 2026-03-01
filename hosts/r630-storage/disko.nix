{ ... }:

let
  osDisk = "/dev/disk/by-id/ata-INTEL_SSDSC2BB300G4_BTWL330500Y5300PGN";

  # Reliable pool members (mirrors).
  d960a = "/dev/disk/by-id/ata-SDLFNCAR-960G-1HA2_0004FF18";
  d960b = "/dev/disk/by-id/ata-SDLFNCAR-960G-1HA2_0004FFF5";
  d960c = "/dev/disk/by-id/ata-TOSHIBA_THNSN8960PCSE_56QS100VTB1V";
  d960d = "/dev/disk/by-id/ata-SAMSUNG_MZ7LM960HCHP-00003_S1YHNXAG801709";

  d480a = "/dev/disk/by-id/ata-TOSHIBA_THNSN8480PCSE_766S103ATAYV";
  d480b = "/dev/disk/by-id/ata-TOSHIBA_THNSN8480PCSE_766S1017TAYV";

  d300a = "/dev/disk/by-id/ata-INTEL_SSDSA2CW300G3_CVPR218600VP300EGN";
  d300b = "/dev/disk/by-id/ata-INTEL_SSDSA2CW300G3_CVPR2185017X300EGN";

  # Bulk/scratch pool member.
  d1920 = "/dev/disk/by-id/ata-TOSHIBA_THNSF81Q92CSE_17FS100GTELT";
in
{
  disko.devices = {
    disk = {
      os = {
        type = "disk";
        device = osDisk;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512MiB";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };

            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                extraArgs = [ "-L" "nixos-root" ];
              };
            };
          };
        };
      };
    };

    zpool = {
      r630-main = {
        type = "zpool";
        mode = {
          topology = {
            vdev = [
              { mode = "mirror"; members = [ d960a d960b ]; }
              { mode = "mirror"; members = [ d960c d960d ]; }
              { mode = "mirror"; members = [ d480a d480b ]; }
              { mode = "mirror"; members = [ d300a d300b ]; }
            ];
          };
        };
        options = {
          ashift = "12";
        };
        rootFsOptions = {
          compression = "lz4";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          mountpoint = "none";
        };
        datasets = {
          "k3s/pv" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/zfs-pv/reliable";
            options = {
              canmount = "on";
              recordsize = "16K";
            };
          };
        };
      };

      r630-bulk = {
        type = "zpool";
        mode = {
          topology = {
            vdev = [
              { members = [ d1920 ]; }
            ];
          };
        };
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "lz4";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          mountpoint = "none";
        };
        datasets = {
          "k3s/pv" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/zfs-pv/bulk";
            options = {
              canmount = "on";
              recordsize = "1M";
            };
          };
        };
      };
    };
  };
}
