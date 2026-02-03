{ config, lib, pkgs, ... }:

let
  hasReadOnlyKubeconfigSecret = builtins.pathExists ../../secrets/kubeconfig-ro.age;
in
{
  # Optional: if you create `secrets/kubeconfig-ro.age` (via agenix), workers will
  # have a read-only kubeconfig at `/home/admin/.kube/config` pointing at the master.
  #
  # This is intentionally opt-in (the secret must exist), to avoid accidentally
  # distributing cluster-admin credentials to all nodes.
  warnings =
    lib.optional (!hasReadOnlyKubeconfigSecret)
      "k8nix: secrets/kubeconfig-ro.age not found; worker kubectl will not be configured.";

  services.k3s = {
    enable = true;
    role = "agent";

    serverAddr = "https://pi-master-1:6443";

    # Must match the master's token
    tokenFile = "/etc/k3s/token";

    extraFlags = lib.concatStringsSep " " [
      "--flannel-backend=vxlan"
    ];
  };

  systemd.tmpfiles.rules = [
    "f /etc/k3s/token 0600 root root - CHANGEME_SUPER_SECRET_TOKEN"
  ] ++ lib.optionals hasReadOnlyKubeconfigSecret [
    "d /home/admin/.kube 0700 admin users - -"
    "L+ /home/admin/.kube/config - - - - /run/agenix/kubeconfig-ro"
  ];

  age.secrets = lib.mkIf hasReadOnlyKubeconfigSecret {
    kubeconfig-ro = {
      file = ../../secrets/kubeconfig-ro.age;
      owner = "admin";
      group = "users";
      mode = "0400";
    };
  };

  environment.sessionVariables = lib.mkIf hasReadOnlyKubeconfigSecret {
    KUBECONFIG = "/home/admin/.kube/config";
  };
}
