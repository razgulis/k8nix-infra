{ config, lib, pkgs, ... }:

let
  cfg = config.k8nix.ingress;
in
{
  options.k8nix.ingress = {
    enable = lib.mkEnableOption "ingress-nginx + MetalLB ingress stack";

    loadBalancerIP = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.206";
      description = ''
        Stable LAN IP announced by MetalLB and used by ingress-nginx for
        host-based HTTP routing.
      '';
    };

    addressPoolName = lib.mkOption {
      type = lib.types.str;
      default = "lan";
      description = "MetalLB address pool name used by ingress-nginx.";
    };

    ingressClassName = lib.mkOption {
      type = lib.types.str;
      default = "nginx";
      description = "IngressClass name provided by ingress-nginx.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Keep ingress/LB manifests under k3s auto-reconciled manifests.
    systemd.tmpfiles.rules = [
      "d /var/lib/rancher/k3s/server/manifests 0755 root root - -"
      "L+ /var/lib/rancher/k3s/server/manifests/metallb.yaml - - - - /etc/k3s/metallb.yaml"
      "L+ /var/lib/rancher/k3s/server/manifests/ingress-nginx.yaml - - - - /etc/k3s/ingress-nginx.yaml"
    ];

    environment.etc."k3s/metallb.yaml".text = ''
      apiVersion: helm.cattle.io/v1
      kind: HelmChart
      metadata:
        name: metallb
        namespace: kube-system
      spec:
        repo: https://metallb.github.io/metallb
        chart: metallb
        targetNamespace: metallb-system
        createNamespace: true
    '';

    environment.etc."k3s/ingress-nginx.yaml".text = ''
      apiVersion: helm.cattle.io/v1
      kind: HelmChart
      metadata:
        name: ingress-nginx
        namespace: kube-system
      spec:
        repo: https://kubernetes.github.io/ingress-nginx
        chart: ingress-nginx
        targetNamespace: ingress-nginx
        createNamespace: true
        valuesContent: |-
          controller:
            replicaCount: 2
            nodeSelector:
              k8nix.io/role: worker
            ingressClassResource:
              name: ${cfg.ingressClassName}
              enabled: true
              default: true
            ingressClass: ${cfg.ingressClassName}
            watchIngressWithoutClass: false
            service:
              type: LoadBalancer
              loadBalancerIP: ${cfg.loadBalancerIP}
              annotations:
                metallb.universe.tf/address-pool: ${cfg.addressPoolName}
    '';

    # MetalLB CRDs are installed by Helm. Apply pool/advertisement after CRDs exist.
    environment.etc."k3s/metallb-pool.yaml".text = ''
      apiVersion: metallb.io/v1beta1
      kind: IPAddressPool
      metadata:
        name: ${cfg.addressPoolName}
        namespace: metallb-system
      spec:
        addresses:
          - ${cfg.loadBalancerIP}-${cfg.loadBalancerIP}
      ---
      apiVersion: metallb.io/v1beta1
      kind: L2Advertisement
      metadata:
        name: ${cfg.addressPoolName}
        namespace: metallb-system
      spec:
        ipAddressPools:
          - ${cfg.addressPoolName}
    '';

    systemd.services.k3s-metallb-bootstrap = {
      description = "Apply MetalLB IPAddressPool/L2Advertisement";
      after = [ "k3s.service" ];
      wants = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [
        config.environment.etc."k3s/metallb-pool.yaml".source
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.kubectl pkgs.coreutils ];
      script = ''
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

        for _ in $(seq 1 180); do
          if kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1; then
            break
          fi
          sleep 5
        done

        kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1
        kubectl apply -f /etc/k3s/metallb-pool.yaml
      '';
    };
  };
}
