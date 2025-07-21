#!/bin/bash
set -e

DISK="/dev/sda"
HOSTNAME="archlinux"
USERNAME="archuser"
PASSWORD="password"  # You should prompt this securely in real usage
LOCALE="en_US.UTF-8"
TIMEZONE="Europe/London"
KEYMAP="us"

# --- Disk Partitioning ---
echo "[*] Wiping and partitioning $DISK..."
sgdisk --zap-all $DISK
parted $DISK --script mklabel msdos
parted $DISK --script mkpart primary 1MiB 100%
parted $DISK --script set 1 boot on

echo "[*] Setting up LUKS encryption..."
echo -n "$PASSWORD" | cryptsetup luksFormat ${DISK}1 -
echo -n "$PASSWORD" | cryptsetup open ${DISK}1 cryptroot -

echo "[*] Creating BTRFS filesystem..."
mkfs.btrfs /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt

# Optional: create BTRFS subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

# Remount subvolumes
mount -o noatime,compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
mkdir /mnt/home
mount -o noatime,compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home

mkdir /mnt/boot

# --- Base System Install ---
echo "[*] Installing base system..."
pacstrap /mnt base linux linux-firmware linux-headers btrfs-progs grub dosfstools networkmanager sudo vim gnome gnome-extra xorg xdg-utils xdg-user-dirs git

# --- FSTAB ---
genfstab -U /mnt >> /mnt/etc/fstab

# --- Chroot and Configure ---
arch-chroot /mnt /bin/bash <<EOF
set -e

echo "[*] Setting timezone..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "[*] Setting locale..."
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

echo "[*] Setting keymap..."
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

echo "[*] Setting hostname..."
echo "$HOSTNAME" > /etc/hostname
echo "127.0.1.1  $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

echo "[*] Creating initramfs with encrypt hook..."
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

echo "[*] Setting root password..."
echo "root:$PASSWORD" | chpasswd

echo "[*] Creating user: $USERNAME"
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "[*] Installing GRUB for BIOS..."
grub-install --target=i386-pc $DISK
UUID=\$(blkid -s UUID -o value ${DISK}1)
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$UUID:cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

echo "[*] Enabling services..."
systemctl enable NetworkManager
systemctl enable gdm
EOF

echo "[*] Installation complete. You can reboot now."

