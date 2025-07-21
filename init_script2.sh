#!/bin/bash
set -euo pipefail

DISK="/dev/nvme0n1"
EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"

echo "=== Enabling NTP ==="
timedatectl set-ntp true

echo "=== Updating Keyring ==="
pacman -Sy --noconfirm archlinux-keyring

echo "=== Partitioning Disk: $DISK ==="
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI System Partition" "$DISK"
sgdisk -n 2:0:0   -t 2:8300 -c 2:"Linux Root Partition" "$DISK"
partprobe "$DISK"

echo "=== Formatting Partitions ==="
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"

echo "=== Mounting Partitions ==="
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

echo "=== Running archinstall with automation ==="
archinstall --config <(cat <<EOF
{
  "version": "2.6.1",
  "mirror-region": {
    "country": "United States"
  },
  "keyboard-layout": "us",
  "locale": "en_US",
  "timezone": "UTC",
  "drive": {
    "$DISK": {
      "wipe": false,
      "partitions": {
        "1": {
          "mount": "/boot",
          "filesystem": "fat32"
        },
        "2": {
          "mount": "/",
          "filesystem": "ext4"
        }
      }
    }
  },
  "bootloader": "grub-install",
  "kernel": "linux",
  "microcode": "amd-ucode",
  "swap": {
    "size": "auto"
  },
  "hostname": "archlinux",
  "root-password": "changeme",
  "user-account": [
    {
      "username": "user",
      "password": "changeme",
      "superuser": true
    }
  ],
  "profile": {
    "desktop-environment": "gnome",
    "greeter": "sddm"
  },
  "audio": "pipewire",
  "gpu-driver": "amd-open",
  "networking": {
    "network-manager": true
  },
  "additional-packages": [
    "firefox", "flatpak", "nano", "gcc", "clang", "make", "cmake",
    "btop", "htop", "nvtop"
  ],
  "multilib": true
}
EOF
)

echo "=== Post-install: Installing GRUB inside chroot ==="
arch-chroot /mnt bash -c "
  pacman -Sy --noconfirm grub efibootmgr dosfstools mtools
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
  grub-mkconfig -o /boot/grub/grub.cfg
"

echo "=== Cleaning up and rebooting ==="
umount -R /mnt
reboot

