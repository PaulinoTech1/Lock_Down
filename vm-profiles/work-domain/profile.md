# CURRENT: work-domain production template

This is the only proposed daily work-domain profile for the two-domain
architecture. Its guest is assumed fully compromised. The XML is a repository
template, **not a deployed domain**. Do not run `virsh define` against the
ThinkPad until the owner approves a disposable test and the current libvirt,
device identity, disk image, and local viewer are verified.

`domain.xml` provides a local SPICE display with clipboard and file transfer
explicitly disabled, one USB MT7921U hostdev, and one guest disk. It contains
no virtual NIC, libvirt network, bridge, NAT, host filesystem, guest agent,
USB redirection, or PCI passthrough. The source disk path is an example
requiring a separately created, backed-up image and storage containment review.
The 8 GiB RAM and four vCPU values are starting points, not measured limits.

VID:PID alone cannot authenticate a physical USB device. The live controller
must prove the approved port/physical path is unique and verify current USB
ownership before launching. The work guest must have autostart disabled; that
property lives in libvirt state, outside domain XML. A static validator cannot
prove either property. `scripts/validate-work-domain.py` validates the template
structure, then the read-only isolation verifier checks live state.

The `<listen type='none'/>` display requires a viewer that obtains a graphics
file descriptor through libvirt. Verify this workflow on a disposable guest
before using it as the daily desktop. Libvirt documents [the graphics listen
types and SPICE clipboard/file-transfer controls](https://libvirt.org/formatdomain.html).
