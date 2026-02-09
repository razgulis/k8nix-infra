let
  # Your laptop key (lets you edit/rekey secrets locally)
  laptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOW8xWUfi/PtattP6DK+kQ74ynKikXPWx+OPkPN73ROG sergei.razgulin@gmail.com";

  # Paste each node’s /etc/ssh/ssh_host_ed25519_key.pub here:
  hosts = {
    "pi-master-1" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMy5MgoFs0BgZAwJWbUlOpkFrzlvZAzVOZMl8gan5JJh root@pi-master-1";
    "pi-worker-1" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM6ujLebyeMT2iipj/PysxQrR5uxCrLwLptsW5fkX491 root@pi-worker-1";
#    "pi-worker-2" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... w2 ...";
#    "pi-worker-3" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... w3 ...";
  };

  k3sNodes = [
    laptop
    hosts."pi-master-1"
    hosts."pi-worker-1"
#    hosts."pi-worker-2"
#    hosts."pi-worker-3"
  ];
in
{
  "k3s-token.age".publicKeys = k3sNodes;
  "kubeconfig-ro.age".publicKeys = k3sNodes;
}
