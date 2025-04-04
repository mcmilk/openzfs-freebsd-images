#!/usr/bin/env bash

######################################################################
# 2) start qemu with some operating system, init via cloud-init
######################################################################

set -eu

# 13.3-STABLE
# 14.1-RELEASE
# 15.0-CURRENT
RELEASE="$1"

# need some old image:
NIC="virtio"
case ${1:0:2} in
  13)
    FILE="amd64-freebsd-13.4-STABLE.qcow2.zst"
    NIC="rtl8139"
    ;;
  14)
    FILE="amd64-freebsd-14.2-STABLE.qcow2.zst"
    ;;
  15)
    FILE="amd64-freebsd-15.0-CURRENT.qcow2.zst"
    ;;
  *)
    echo "Wrong FreeBSD Version"
    exit 111
    ;;
esac
REL="v2024-12-30"
URL="https://github.com/mcmilk/openzfs-freebsd-images/releases/download/$REL/$FILE"

IMG="/mnt/cloudimg.qcow2"
DISK="/mnt/freebsd.qcow2"
sudo chown -R $(whoami) /mnt

echo "Loading image $URL ..."
time axel -q -o "$IMG.zst" "$URL"
zstd -q -d --rm "$IMG.zst"

# we use zstd for faster IO on the testing runner
echo "Converting image ..."
qemu-img convert -q -f qcow2 -O qcow2 -c \
  -o compression_type=zstd,preallocation=off $IMG $DISK
rm -f $IMG

echo "Resizing image to 32GiB ..."
qemu-img resize -q $DISK 32G

# generate ssh keys
rm -f ~/.ssh/id_ed25519
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -q -N ""
PUBKEY=`cat ~/.ssh/id_ed25519.pub`
BASH="/usr/local/bin/bash"

cat <<EOF > /tmp/user-data
#cloud-config

fqdn: freebsd

# user:zfs password:1
users:
- name: root
  shell: $BASH
- name: zfs
  sudo: ALL=(ALL) NOPASSWD:ALL
  shell: $BASH
  lock-passwd: false
  passwd: \$1\$EjKAQetN\$O7Tw/rZOHaeBP1AiCliUg/
  ssh_authorized_keys:
    - $PUBKEY

growpart:
  mode: auto
  devices: ['/']
  ignore_growroot_disabled: false
EOF

sudo virsh net-update default add ip-dhcp-host \
  "<host mac='52:54:00:83:79:00' ip='192.168.122.10'/>" --live --config

sudo virt-install \
  --os-variant freebsd14.0 \
  --name "openzfs" \
  --cpu host-passthrough \
  --virt-type=kvm --hvm \
  --vcpus=4,sockets=1 \
  --memory $((1024*8)) \
  --graphics none \
  --network bridge=virbr0,model=$NIC,mac='52:54:00:83:79:00' \
  --cloud-init user-data=/tmp/user-data \
  --disk $DISK,format=qcow2,bus=virtio \
  --import --noautoconsole 2>/dev/null
