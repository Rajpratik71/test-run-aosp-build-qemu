#!/bin/sh

while getopts "rs" opt
do
	case "$opt" in
	s)	sw_render='qemu=1';;
	r)	use_remote_display=1;;
	[?])	echo "syntax: `basename $0` [-rs]\n" \
		"  -r Enable remote display (spice)\n" \
		"  -s Use software rendering"
		exit 1;;
	esac
done
shift $((OPTIND-1))

ARCH=arm

QEMU_ARCH=$ARCH

if [ -z "${sw_render}" ]; then
	QEMU_DISPLAY="-device virtio-gpu-pci,virgl"
else
	QEMU_DISPLAY="-device VGA"
fi

if [ -n "${use_remote_display}" ]; then
	QEMU_DISPLAY="${QEMU_DISPLAY} -spice port=5900,disable-ticketing"
else
	if [ -z "${sw_render}" ]; then
		QEMU_DISPLAY="${QEMU_DISPLAY} -display gtk,gl=on"
	else
		QEMU_DISPLAY="${QEMU_DISPLAY} -display gtk"
	fi
fi

case "$ARCH" in
arm)
	QEMU_OPTS="-cpu cortex-a15 -machine type=virt"
	KERNEL_CMDLINE='console=ttyAMA0,38400 nosmp'
	KERNEL=boot.img
	;;
arm64*)
	QEMU_ARCH="aarch64"
	QEMU_OPTS="-cpu cortex-a57 -machine type=virt"
	KERNEL_CMDLINE='console=ttyAMA0,38400'
	KERNEL=boot.img
	;;
x86_64)
	KERNEL=boot.img
	QEMU_OPTS="-enable-kvm -smp 4"
	KERNEL_CMDLINE='console=ttyS0'
	;;
x86)
	QEMU_ARCH="x86_64"
	KERNEL=boot.img
	QEMU_OPTS="-enable-kvm -smp 2"
	KERNEL_CMDLINE='console=ttyS0'
	;;
esac

if [ ! -f system.raw -o system.img -nt system.raw ]; then
	simg2img system.img system.raw
fi

if [ ! -f cache.raw -o system.raw -nt cache.raw ]; then
	rm -f cache.raw userdata.raw
	mkfs.ext4 -L cache cache.raw 256M
	mkfs.ext4 -L data userdata.raw 1024M
fi

qemu-system-${QEMU_ARCH} \
	${QEMU_OPTS} \
	-append "${KERNEL_CMDLINE} vt.global_cursor_default=0 androidboot.selinux=permissive debug drm.debug=0 ${sw_render}" \
	-m 2024 \
	-serial mon:stdio \
	-kernel $KERNEL \
	-initrd ramdisk.img \
	-drive index=0,if=none,id=system,file=system.raw \
	-device virtio-blk-pci,drive=system \
	-drive index=1,if=none,id=cache,file=cache.raw \
	-device virtio-blk-pci,drive=cache \
	-drive index=2,if=none,id=userdata,file=userdata.raw \
	-device virtio-blk-pci,drive=userdata \
	-netdev user,id=mynet,hostfwd=tcp::5400-:5555 -device virtio-net-pci,netdev=mynet \
	-device virtio-mouse-pci -device virtio-keyboard-pci \
	-d guest_errors \
	-nodefaults \
	${QEMU_DISPLAY} \
	$*
