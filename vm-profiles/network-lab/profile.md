# Profile: network-lab

Multi-VM lab with inter-VM segmentation. At least one VM is treated as
hostile to the others (e.g., attacker, victim, observer). Segmentation is
enforced host-side in nftables so the policy is visible in one place.
Full threat model: `../../docs/VM_THREAT_MODELS.md` (Profile 3).
Host-side hardening: `../../docs/KVM_SECURITY.md`.

Tradeoff note: host-side nftables is chosen over a router VM on purpose. A
router VM is itself a VM that can be compromised, at which point it owns
the segmentation. Host-side rules keep the enforcement point outside every
guest's reach. Cost: the rule set is hand-authored and must be reviewed
like firewall rules, because they are firewall rules.

## Preconditions (LOCAL, run on the host)

- `scripts/check-iommu.sh` passes.
- AppArmor enforce mode; libvirt `security_driver = "apparmor"`.
- KSM off: `/sys/kernel/mm/ksm/run` reads `0`. (Memory use scales linearly
  with VM count; keep the lab to 2-4 small VMs on this laptop.)
- No shared host filesystems, no USB redirect, no PCI passthrough on any
  lab VM (same prohibitions as untrusted-analysis).

## Lab networks

One libvirt network per segment. Example: two segments, attacker and
victim.

```xml
<network>
  <name>lab-attacker</name>
  <forward mode='nat'/>
  <ip address='192.168.210.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.210.10' end='192.168.210.50'/>
    </dhcp>
  </ip>
</network>
```

```xml
<network>
  <name>lab-victim</name>
  <forward mode='nat'/>
  <ip address='192.168.220.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.220.10' end='192.168.220.50'/>
    </dhcp>
  </ip>
</network>
```

## nftables segmentation (host side)

Default deny between zones; open only documented holes:

```nft
table inet vm_lab {
  chain forward {
    type filter hook forward priority 0; policy drop;

    # Established return traffic.
    ct state established,related accept

    # Documented hole 1: victim may initiate outbound (updates, DNS).
    # Replace with the lab's actual expected traffic.
    iifname "virbr-lab-victim" oifname != "virbr-lab-attacker" accept

    # Documented hole 2: attacker may initiate to victim on lab ports.
    iifname "virbr-lab-attacker" oifname "virbr-lab-victim" \
      tcp dport { 22, 80, 443 } accept

    # Everything else between lab zones: dropped and logged.
    iifname "virbr-lab-*" log prefix "lab-drop: " drop
  }
}
```

Notes:

- Interface names (`virbr-lab-attacker`) are examples; use the actual
  bridge names libvirt creates and verify with `ip link`. Do not guess.
- Each allow rule carries a comment naming the lab scenario it serves.
  Rules without a scenario get removed in review.
- Log drops during lab development; keep logging on for the hostile
  segment in production use.

## virt-install example (one lab VM)

```bash
virt-install \
  --name lab-victim-01 \
  --vcpus 2 \
  --memory 2048 \
  --disk /var/lib/libvirt/images/lab-victim-01.qcow2,size=30,bus=virtio,cache=none \
  --os-variant debian13 \
  --network network=lab-victim,model=virtio \
  --graphics none \
  --noautoconsole
```

- `--graphics none`: lab VMs are headless; console via `virsh console`.
  Removes the SPICE attack surface entirely.
- Repeat per VM on its segment's network. No `--filesystem`, no
  `--redirdev`, no `--hostdev` on any lab VM.

## libvirt XML excerpt (per lab VM)

```xml
<domain type='kvm'>
  <name>lab-victim-01</name>
  <cpu mode='host-passthrough'/>
  <devices>
    <interface type='network'>
      <source network='lab-victim'/>
      <model type='virtio'/>
      <!-- No vhost: same reasoning as untrusted-analysis. -->
    </interface>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/lab-victim-01.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <!-- No graphics, no filesystem, no redirdev, no hostdev. -->
  </devices>
  <seclabel type='dynamic' model='apparmor' relabel='yes'/>
</domain>
```

## What this profile does NOT protect against

- VM escape, microarchitectural side channels between co-resident lab VMs
  and the host, misconfiguration of the rule set (rule sprawl is the
  observed failure mode; review on every lab change), hostile-VM attacks
  on in-segment virtual network behavior (ARP spoofing inside its own
  segment is expected lab behavior, contained by segmentation).

## Recovery

- Compromised lab VM: isolate its segment at the nftables level first
  (drop its zone), then snapshot for forensics, then rebuild the VM from a
  clean image. Do not trust the segmentation rules until re-verified after
  any incident.
