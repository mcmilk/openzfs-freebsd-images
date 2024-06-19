#!/usr/bin/env bash

######################################################################
# 3) build amd64 freebsd images for openzfs testings
######################################################################

set -eu

function build {
    VERSION="$1"
    RELEASE="$2"
    BASE_URL="https://download.freebsd.org/ftp/snapshots/amd64/$RELEASE"
    IMAGE="amd64-freebsd-$VERSION.raw"
    IMAGE2="amd64-freebsd-$RELEASE.qcow2"

    MNT="/mnt/$VERSION"
    mkdir -p $MNT

    gptboot=/boot/gptboot

    echo "Generating boot configuration..."
    dd if=/dev/zero of=$IMAGE bs=1048576 count=6000
    md_dev=$(mdconfig -a -t vnode -f $IMAGE)
    gpart create -s gpt ${md_dev}
    gpart add -t freebsd-boot -s 1024 ${md_dev}
    gpart bootcode -b /boot/pmbr -p ${gptboot} -i 1 ${md_dev}
    gpart add -t efi -s 40M ${md_dev}
    gpart add -s 1G -l swapfs -t freebsd-swap ${md_dev}
    gpart add -t freebsd-ufs -l rootfs ${md_dev}
    newfs_msdos -F 32 -c 1 /dev/${md_dev}p2
    mount -t msdosfs /dev/${md_dev}p2 $MNT
    mkdir -p $MNT/EFI/BOOT
    cp /boot/loader.efi $MNT/EFI/BOOT/BOOTX64.efi
    umount $MNT

    newfs -U -L FreeBSD /dev/${md_dev}p4
    mount /dev/${md_dev}p4 $MNT

    echo "Downloading base.txz, kernel.txz and src.txz ..."
    axel -q ${BASE_URL}/base.txz   -o base-$VERSION.txz
    axel -q ${BASE_URL}/kernel.txz -o kernel-$VERSION.txz
    axel -q ${BASE_URL}/src.txz    -o src-$VERSION.txz

    echo "Extracting base.txz, kernel.txz and src.txz ..."
    cat base-$VERSION.txz   | tar xf - -C $MNT
    cat kernel-$VERSION.txz | tar xf - -C $MNT
    cat src-$VERSION.txz    | tar xf - -C $MNT

    echo "Installing cloud-init ..."
    echo "
export ASSUME_ALWAYS_YES=YES
pkg install bash ca_root_nss py311-cloud-init git npm qemu-guest-agent
chsh -s /usr/local/bin/bash root
pw mod user root -w no
touch /etc/rc.conf
" > $MNT/tmp/cloudify.sh

    echo "pw mod user root -w no" >> $MNT/tmp/cloudify.sh
    chmod +x $MNT/tmp/cloudify.sh

    cp /etc/resolv.conf $MNT/etc/resolv.conf
    mount -t devfs devfs $MNT/dev
    chroot $MNT /tmp/cloudify.sh
    umount $MNT/dev
    rm $MNT/tmp/cloudify.sh

    echo "Setup configuration ..."
    echo '' > $MNT/etc/resolv.conf
    echo '/dev/gpt/rootfs   /     ufs  rw   1   1' >> $MNT/etc/fstab
    echo '/dev/gpt/swapfs  none  swap  sw   0   0' >> $MNT/etc/fstab

    echo 'autoboot_delay="-1"' >> $MNT/boot/loader.conf
    echo 'loader_logo="none"' >> $MNT/boot/loader.conf
    echo 'beastie_disable="YES"' >> $MNT/boot/loader.conf
    echo 'boot_serial="YES"' >> $MNT/boot/loader.conf
    echo 'boot_multicons="YES"' >> $MNT/boot/loader.conf
    echo 'comconsole_speed="115200"' >> $MNT/boot/loader.conf
    echo 'console="comconsole,vidconsole,spinconsole"' >> $MNT/boot/loader.conf

    echo '-P' >> $MNT/boot.config
    rm -rf $MNT/tmp/*
    echo 'cloudinit_enable="YES"' >> $MNT/etc/rc.conf
    echo 'sendmail_enable="NONE"' >> $MNT/etc/rc.conf
    echo 'sshd_enable="YES"' >> $MNT/etc/rc.conf
    echo 'growfs_enable="YES"' >> $MNT/etc/rc.conf
    echo 'rtsold_enable="YES"' >> $MNT/etc/rc.conf
    echo 'fsck_y_enable="YES"' >> $MNT/etc/rc.conf
    echo 'qemu_guest_agent_enable="YES"' >> $MNT/etc/rc.conf
    echo 'qemu_guest_agent_flags="-d -v -l /var/log/qemu-ga.log"' >> $MNT/etc/rc.conf

    echo "Used space:"
    df -h $MNT
    umount /dev/${md_dev}p4
    mdconfig -du ${md_dev}

    echo "Converting image from raw to qcow2..."
    qemu-img convert -f raw -O qcow2 $IMAGE $IMAGE2
    zstd $IMAGE2
    ls -lha amd*
}

export ASSUME_ALWAYS_YES="YES"
pkg remove -y qemu-guest-agent
pkg install -y axel qemu-tools rsync

# build "14.1" "14.1-STABLE"
REL="$1"
VER="${1:0:4}"
build $VER $REL
