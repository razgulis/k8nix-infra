{ config, lib, pkgs, ... }:

let
  cfg = config.k8nix.argocd;
  bootstrapManifest =
    lib.concatStringsSep "\n" (
      [
        "apiVersion: argoproj.io/v1alpha1"
        "kind: AppProject"
        "metadata:"
        "  name: ${cfg.projectName}"
        "  namespace: ${cfg.namespace}"
        "spec:"
        "  sourceRepos:"
      ]
      ++ (map (repo: "  - ${builtins.toJSON repo}") cfg.allowedSourceRepos)
      ++ [
        "  destinations:"
        "  - namespace: \"*\""
        "    server: https://kubernetes.default.svc"
        "  clusterResourceWhitelist:"
        "  - group: \"*\""
        "    kind: \"*\""
        "---"
        "apiVersion: argoproj.io/v1alpha1"
        "kind: Application"
        "metadata:"
        "  name: ${cfg.bootstrapApp.name}"
        "  namespace: ${cfg.namespace}"
        "spec:"
        "  project: ${cfg.projectName}"
        "  source:"
        "    repoURL: ${cfg.bootstrapApp.repoURL}"
        "    targetRevision: ${cfg.bootstrapApp.targetRevision}"
        "    path: ${cfg.bootstrapApp.path}"
        "    directory:"
        "      recurse: true"
        "  destination:"
        "    namespace: ${cfg.namespace}"
        "    server: https://kubernetes.default.svc"
        "  syncPolicy:"
        "    automated:"
        "      prune: true"
        "      selfHeal: true"
        "    syncOptions:"
        "    - CreateNamespace=true"
        "    - ApplyOutOfSyncOnly=true"
      ]
    )
    + "\n";
in
{
  options.k8nix.argocd = {
    enable = lib.mkEnableOption "Argo CD bootstrap for the k3s cluster";

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "argocd";
      description = "Namespace where Argo CD is deployed.";
    };

    projectName = lib.mkOption {
      type = lib.types.str;
      default = "k8nix";
      description = "Argo CD AppProject used by cluster applications.";
    };

    allowedSourceRepos = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "https://github.com/razgulis/k8nix-apps*"
        "https://gitlab.gitlab.svc.cluster.local/*/*"
      ];
      description = ''
        Repositories this Argo CD project can sync from. The second entry is a
        placeholder pattern for an in-cluster GitLab instance.
      '';
    };

    bootstrapApp = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "k8nix-apps";
        description = "Root Argo CD Application name (app-of-apps).";
      };

      repoURL = lib.mkOption {
        type = lib.types.str;
        default = "https://github.com/razgulis/k8nix-apps";
        description = "Repository used to bootstrap Argo CD applications.";
      };

      targetRevision = lib.mkOption {
        type = lib.types.str;
        default = "master";
        description = "Git revision tracked by the bootstrap application.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "argocd";
        description = "Path in the bootstrap repository that contains Argo manifests.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/rancher/k3s/server/manifests 0755 root root - -"
      "L+ /var/lib/rancher/k3s/server/manifests/argocd.yaml - - - - /etc/k3s/argocd.yaml"
    ];

    environment.etc."k3s/argocd.yaml".text = ''
      apiVersion: helm.cattle.io/v1
      kind: HelmChart
      metadata:
        name: argocd
        namespace: kube-system
      spec:
        repo: https://argoproj.github.io/argo-helm
        chart: argo-cd
        targetNamespace: ${cfg.namespace}
        createNamespace: true
        valuesContent: |-
          configs:
            params:
              server.insecure: true
          server:
            service:
              type: ClusterIP
    '';

    environment.etc."k3s/argocd-bootstrap.yaml".text = bootstrapManifest;

    # Apply AppProject/Application only after Argo CD CRDs exist.
    systemd.services.k3s-argocd-bootstrap = {
      description = "Apply Argo CD bootstrap resources";
      after = [ "k3s.service" ];
      wants = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [
        config.environment.etc."k3s/argocd-bootstrap.yaml".source
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.kubectl pkgs.coreutils ];
      script = ''
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

        for _ in $(seq 1 180); do
          if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
            break
          fi
          sleep 5
        done

        kubectl get crd applications.argoproj.io >/dev/null 2>&1
        kubectl apply -f /etc/k3s/argocd-bootstrap.yaml
      '';
    };
  };
}
