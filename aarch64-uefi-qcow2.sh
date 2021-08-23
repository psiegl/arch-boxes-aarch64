#!/bin/sh

# Overwrite from cli if required
ARCHVER=${ARCHVER:-ArchLinuxARM-aarch64-latest}
IMGSIZE=${IMGSIZE:-16G}


TMPDEV=/dev/nbd0
TMPDIR="${ARCHVER}-sysroot"

# Ten64/muvirt: https://ten64doc.traverse.com.au/applications/doesitrun/
# https://xnand.netlify.app/2019/10/03/armv8-qemu-efi-aarch64.html
# https://www.dinotools.de/2015/06/09/mount-qcow2-disk-image/
# https://www.dokuwiki.tachtler.net/doku.php?id=tachtler:archlinux_-_minimal_server_installation_uefi-boot
# https://ten64doc.traverse.com.au/software/recovery/#arch-setup (highlights to install linux-aarch64-rc)
#pacman -S qemu-headless # get qemu-nbd,qemu-img
#pacman -S parted

echo "Creating qcow2 with size ${IMGSIZE}"
IMG="${ARCHVER}.qcow2"
qemu-img create -f qcow2 $IMG $IMGSIZE

modprobe nbd max_part=8
qemu-nbd --connect=$TMPDEV $IMG

parted $TMPDEV mktable gpt \
	       mkpart ESP fat32 1MiB 513MiB \
	       set 1 boot on \
	       mkpart primary ext4 513MiB 100% \
	       print

mkfs.vfat -F 32 -n "AARCH64_EFI" "${TMPDEV}p1"
mkfs.ext4 -m 1 "${TMPDEV}p2"

mkdir -p $TMPDIR
mount "${TMPDEV}p2" $TMPDIR

mkdir $TMPDIR/boot
mount "${TMPDEV}p1" $TMPDIR/boot

curl -O "http://de4.mirror.archlinuxarm.org/os/${ARCHVER}.tar.gz"
bsdtar -xpf "${ARCHVER}.tar.gz" -C $TMPDIR
sync

VDA_BOOT=$(blkid -s PARTUUID -o value "${TMPDEV}p1")
VDA_ROOT=$(blkid -s PARTUUID -o value "${TMPDEV}p2")

# in case running on aarch64: genfstab -Up /mnt >> /mnt/etc/fstab
echo "Setting up fstab"
cat << EOF > $TMPDIR/etc/fstab
# Static information about the filesystems.
# See fstab(5) for details.

# <file system> <dir> <type> <options> <dump> <pass>
PARTUUID=${VDA_BOOT}	/boot     	vfat      	rw,defaults	0 2
PARTUUID=${VDA_ROOT}	/         	ext4      	rw,relatime	0 1
EOF


if [[ "$(uname -m)" == "aarch64" ]]; then
 echo "FixME: run chroot bootctl install"
else
  echo "HACK: Mimic 'bootctl install', no guarantee. Run after first startup!"
  mkdir -p $TMPDIR/boot/EFI/systemd
  cp $TMPDIR/usr/lib/systemd/boot/efi/systemd-bootaa64.efi $TMPDIR/boot/EFI/systemd/systemd-bootaa64.efi
  mkdir -p $TMPDIR/boot/EFI/BOOT
  cp $TMPDIR/usr/lib/systemd/boot/efi/systemd-bootaa64.efi $TMPDIR/boot/EFI/BOOT/BOOTAA64.EFI
fi


echo "Setting up boot loader: loader.conf"
mkdir -p $TMDIR/boot/loader
cat << EOF > $TMDIR/boot/loader/loader.conf
default       arch-efi
timeout       0
editor        no
console-mode  max
auto-entries  0
auto-firmware 1
EOF

echo "Setting up boot loader: arch-efi.conf"
mkdir -p $TMPDIR/boot/loader/entries
cat << EOF > $TMPDIR/boot/loader/entries/arch-efi.conf
title   Arch Linux (EFI)
linux   /Image
initrd  /initramfs-linux.img
options root=PARTUUID=${VDA_ROOT} rw quiet
EOF
echo "Setting up boot loader: arch-fallback-efi.conf"
cat << EOF > $TMPDIR/boot/loader/entries/arch-fallback-efi.conf
title   Arch Linux - Fallback (EFI)
linux   /Image
initrd  /initramfs-linux-fallback.img
options root=PARTUUID=${VDA_ROOT} rw
EOF

# https://wiki.archlinux.org/title/systemd-boot#Automatic_update
echo "Create hook in case of systemd boot update"
cat << EOF > $TMPDIR/usr/share/libalpm/hooks/95-systemd-boot.hook
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot
When = PostTransaction
Exec = /usr/bin/bootctl update
EOF

# Optional, in case EFI boot not functioning, copy to external
#mkdir -p "${IMG}kernel"
#cp $TMPDIR/boot/{Image,initramfs-linux.img} "${IMG}kernel"/.


umount $TMPDIR/boot
umount $TMPDIR

rmdir $TMPDIR

qemu-nbd --disconnect $TMPDEV

# https://archlinuxarm.org/platforms/armv8/generic
echo "Information:"
echo ""
echo "  User: root ; Pass: root"
echo "  User: alarm; Pass: alarm"
echo ""
echo "!!! IMPORTANT !!!"
echo ""
echo "when booting first time, run:"
echo "  pacman-key --init"
echo "  pacman-key --populate archlinuxarm"
if [[ "$(uname -m)" != "aarch64" ]]; then
  echo "  bootctl install"
  echo "  mkinitcpio -p linux-aarch64"
fi
echo ""
echo "you may want to:"
echo "  pacman --noconfirm -Syu"
echo "  pacman --noconfirm -S efibootmgr dosfstools vim htop"

#echo "/etc/config/virt"
#echo "config vm 'patine'"
#        option memory '4096'
#        option numprocs '4'
#        list disks '/vm/vm2.qcow2'
##       option kernel '/vm/Image'
##       option append 'root=/dev/vda2 rw'     # console=ttyAMA0
##       option initrd '/vm/initramfs-linux.img'
#        list network 'lan'
#        option mac '52:54:00:a8:91:1d'
#        option enable '1'
#        option provisioned '1'

