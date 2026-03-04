{ config, lib, pkgs, ... }:

let
  hasK3sTokenSecret = builtins.pathExists ../../secrets/k3s-token.age;
in
{
  warnings =
    lib.optional (!hasK3sTokenSecret)
      "k8nix: secrets/k3s-token.age not found; using placeholder /etc/k3s/token.";

  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;

    tokenFile = if hasK3sTokenSecret then "/run/agenix/k3s-token" else "/etc/k3s/token";

    # Optional opinionated defaults
    extraFlags = lib.concatStringsSep " " [
      "--write-kubeconfig-mode=0644"
      "--disable=traefik"
      "--disable=servicelb"
      "--flannel-backend=vxlan"
      # If you later add MetalLB, you usually want servicelb disabled.
    ];
  };

  # Keep bootstrap convenience when no encrypted token exists.
  systemd.tmpfiles.rules = (lib.optionals (!hasK3sTokenSecret) [
    "f /etc/k3s/token 0600 root root - CHANGEME_SUPER_SECRET_TOKEN"
  ]) ++ [
    "d /var/lib/rancher/k3s/server/manifests 0755 root root - -"
    "L+ /var/lib/rancher/k3s/server/manifests/readonly-kubeconfig-rbac.yaml - - - - /etc/k3s/readonly-kubeconfig-rbac.yaml"
    "d /home/admin/.kube 0700 admin users - -"
    "L+ /home/admin/.kube/config - - - - /etc/rancher/k3s/k3s.yaml"
  ];

  age.secrets = lib.mkIf hasK3sTokenSecret {
    k3s-token = {
      file = ../../secrets/k3s-token.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

  # Helpful to manage from the master
  environment.systemPackages = with pkgs; [
    kubectl
  ];

  # Make `kubectl` work out-of-the-box on the master.
  environment.sessionVariables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";

  # Apply read-only kubeconfig RBAC on the server (used by workers).
  environment.etc."k3s/readonly-kubeconfig-rbac.yaml".text = ''
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: readonly-kubeconfig
      namespace: kube-system
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: node-reader
    rules:
    - apiGroups: [""]
      resources: ["nodes"]
      verbs: ["get", "list", "watch"]
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: readonly-kubeconfig-nodes
    subjects:
    - kind: ServiceAccount
      name: readonly-kubeconfig
      namespace: kube-system
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: node-reader
  '';
}
