{ config, lib, pkgs, ... }:

let
  hasReadOnlyKubeconfigSecret = builtins.pathExists ../../secrets/kubeconfig-ro.age;
  hasK3sTokenSecret = builtins.pathExists ../../secrets/k3s-token.age;
in
{
  # Optional: if you create `secrets/kubeconfig-ro.age` (via agenix), workers will
  # have a read-only kubeconfig at `/home/admin/.kube/config` pointing at the master.
  #
  # This is intentionally opt-in (the secret must exist), to avoid accidentally
  # distributing cluster-admin credentials to all nodes.
  warnings =
    (lib.optional (!hasReadOnlyKubeconfigSecret)
      "k8nix: secrets/kubeconfig-ro.age not found; worker kubectl will not be configured.")
    ++ (lib.optional (!hasK3sTokenSecret)
      "k8nix: secrets/k3s-token.age not found; using placeholder /etc/k3s/token.");

  services.k3s = {
    enable = true;
    role = "agent";

    serverAddr = "https://pi-master-1:6443";

    # Must match the master's token
    tokenFile = if hasK3sTokenSecret then "/run/agenix/k3s-token" else "/etc/k3s/token";

    # Note: `--flannel-backend` is not a valid flag for `k3s agent` (it is a
    # server-side setting). Label agent nodes as workers by default; hosts can
    # still override (for example, storage-specialized nodes).
    extraFlags = lib.mkDefault "--node-label=k8nix.io/role=worker";
  };

  systemd.tmpfiles.rules = (lib.optionals (!hasK3sTokenSecret) [
    "f /etc/k3s/token 0600 root root - CHANGEME_SUPER_SECRET_TOKEN"
  ]) ++ lib.optionals hasReadOnlyKubeconfigSecret [
    "d /home/admin/.kube 0700 admin users - -"
    "L+ /home/admin/.kube/config - - - - /run/agenix/kubeconfig-ro"
  ];

  age.secrets =
    (lib.optionalAttrs hasReadOnlyKubeconfigSecret {
      kubeconfig-ro = {
        file = ../../secrets/kubeconfig-ro.age;
        owner = "admin";
        group = "users";
        mode = "0400";
      };
    })
    // (lib.optionalAttrs hasK3sTokenSecret {
      k3s-token = {
        file = ../../secrets/k3s-token.age;
        owner = "root";
        group = "root";
        mode = "0400";
      };
    });

  environment.sessionVariables = lib.mkIf hasReadOnlyKubeconfigSecret {
    KUBECONFIG = "/home/admin/.kube/config";
  };
}
