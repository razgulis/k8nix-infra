# k8nix

NixOS flake for a multi-node Raspberry Pi 4 k3s cluster.

## What this repo includes
- Flake outputs for one master and four workers, all aarch64.
- Shared base config (SSH, users, kernel params, tools).
- Network defaults (static LAN IPs, /etc/hosts, firewall).
- SD card image build for headless boot.
- k3s server/agent modules and a sample agenix secrets file.

## Requirements
- Nix with flakes enabled.
- Raspberry Pi 4 devices (aarch64).
- SD card writer (and `dd` or a similar tool).
- Optional: agenix for managing the k3s token.

## Layout
- `flake.nix`: entry point; `nixosConfigurations` for each node.
- `modules/base.nix`: common OS defaults and tools.
- `modules/networking.nix`: static IPs, hosts file, firewall rules.
- `modules/sd-image.nix`: SD image builder.
- `modules/k3s/server.nix`: k3s server config.
- `modules/k3s/agent.nix`: k3s agent config.
- `hosts/*/default.nix`: per-node overrides.
- `secrets/secrets.nix`: agenix recipients and example secret mapping.

## Quick start
1) Update host IPs and gateway in `modules/networking.nix`.
2) Update SSH keys and secrets in `secrets/secrets.nix`.
3) Build an SD card image for a node:

```bash
nix build .#nixosConfigurations.pi-master-1.config.system.build.sdImage
```

The image appears in `./result/sd-image/`.

4) Flash the image (example):

```bash
lsblk
sudo umount /dev/sdX1 /dev/sdX2 2>/dev/null || true
sudo dd if=./result/sd-image/nixos-pi-master-1.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

5) Boot the Pi, then repeat for each worker.

Note: flash to the whole device (e.g. `/dev/sda`), not a partition (e.g. `/dev/sda1`).

## Continued Development (updating without reflashing)
- ssh into the instance, then make sure this repository is cloned:
  `mkdir repositories; cd repositories; git clone https://github.com/razgulis/k8nix.git`
- if the repo is already checked out:
  `git pull`
- rebuild the flake you are currently on:
  `sudo nixos-rebuild switch --flake .#pi-worker-X`

## SSH access
- Default user is `admin` (key-based auth; password login is disabled). Update the SSH key and Home Manager defaults in `modules/base.nix`.

## Name resolution
- Nodes advertise `*.local` via mDNS (e.g. `pi-master-1.local`) and can be reached by name on clients that support mDNS.

## DNS (Blocky)
- `pi-master-1` runs `blocky` and listens on port `53` (TCP/UDP).
- The `systemd-resolved` DNS stub listener is disabled on the master so Blocky can bind to `:53`.

## Cluster bootstrap notes
- The k3s token is read from `/etc/k3s/token`.
- A placeholder token is created by tmpfiles rules in the k3s modules.
- For real usage, replace the placeholder with agenix (or another secret manager).

## Worker kubeconfig (read-only)
Workers can optionally have a read-only kubeconfig at `/home/admin/.kube/config` (encrypted via agenix as `secrets/kubeconfig-ro.age`).

High level:
1) Ensure the master has the read-only RBAC manifest applied (after rebuilding `pi-master-1`).
2) Generate a token and write a kubeconfig pointing at `https://pi-master-1:6443`.
3) Encrypt that kubeconfig into `secrets/kubeconfig-ro.age` and rebuild the workers.

After the master rebuild, the RBAC is applied automatically from `/var/lib/rancher/k3s/server/manifests/readonly-kubeconfig-rbac.yaml`.

Example (run on `pi-master-1`):

```bash
TOKEN="$(sudo k3s kubectl -n kube-system create token readonly-kubeconfig --duration=8760h)"
CA_B64="$(sudo base64 -w0 /var/lib/rancher/k3s/server/tls/server-ca.crt)"

cat > /tmp/kubeconfig-ro.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
- name: default
  cluster:
    certificate-authority-data: ${CA_B64}
    server: https://pi-master-1:6443
users:
- name: readonly
  user:
    token: ${TOKEN}
contexts:
- name: default
  context:
    cluster: default
    user: readonly
current-context: default
EOF
```

Then (on your dev machine in this repo):

```bash
nix develop
cd secrets
RULES=./secrets.nix EDITOR=vim agenix -e kubeconfig-ro.age -i ~/.ssh/nix-pi-cluster
```

Paste the contents of `/tmp/kubeconfig-ro.yaml`, save, then rebuild worker nodes/images.

Notes:
- The `laptop` key in `secrets/secrets.nix` must match the public key of the private key you use with `-i`.
- Replace `~/.ssh/nix-pi-cluster` with the private key you actually use on your dev machine.
- If you get `Forbidden: nodes is forbidden`, the RBAC manifest wasn’t applied on the master; rebuild `pi-master-1`.

## Development shell
This flake exposes a dev shell with agenix:

```bash
nix develop
```

## Customize
- Add per-node tweaks in `hosts/<node>/default.nix`.
- Update k3s flags in `modules/k3s/server.nix` or `modules/k3s/agent.nix`.
- If you want DHCP instead of static IPs, flip the commented settings in
  `modules/networking.nix`.
