#!/bin/bash

# Build ArchISO from scratch and setup the environment for development
# Has not been tested for sometime... but you can see the functions below
# and write manually if you wish, get the arch iso from 
# https://archlinux.org/download/

# Filesystem mount warning
echo "This script will create and format the partitions as follows:"
echo "/dev/sda1 - 512Mib will be mounted as /boot/efi"
echo "/dev/sda2 - 1GiB will be used as swap"
echo "/dev/sda3 - rest of space will be mounted as /"


# to create the partitions programatically (rather than manually)
# https://superuser.com/a/984637
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk /dev/sda
  o # clear the in memory partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk 
  +512M # 512 MB boot parttion
  n # new partition
  p # primary partition
  2 # partion number 2
    # default, start immediately after preceding partition
  +1G # 8 GB swap parttion
  n # new partition
  p # primary partition
  3 # partion number 3
    # default, start immediately after preceding partition
    # default, extend partition to end of disk
  a # make a partition bootable
  1 # bootable partition is partition 1 -- /dev/sda1
  p # print the in-memory partition table
  w # write the partition table
  q # and we're done
EOF

# Format the partitions
mkfs.ext4 /dev/sda3
mkfs.fat -F32 /dev/sda1

# Set up time
timedatectl set-ntp true

# Initate pacman keyring
pacman-key --init
pacman-key --populate archlinux
pacman-key --refresh-keys

# pacman setup - create a backup and adding the fastest mirrors first.
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
reflector --verbose --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

# Mount the partitions
mount /dev/sda3 /mnt
mkdir -pv /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi
mkswap /dev/sda2
swapon /dev/sda2

# Install Arch Linux
echo "Starting install.."
echo "Installing Arch Linux" 
pacstrap /mnt/ base base-devel linux linux-firmware net-tools networkmanager vi nano xorg xorg-server gnome gnome-tweaks leafpad git qt5-base qt5-tools make squashfs-tools libisoburn dosfstools patch lynx devtools

# Generate the F-Stab
genfstab -U /mnt >> /mnt/etc/fstab

# Create script to send into the CHROOT directory
cat <<'EOF' >> post.sh
#! /bin/bash
# Set keyboard layout and generate the keyboard
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' locale.gen 
locale-gen
echo "LANG=en_US.UTF-8"  > /etc/locale.conf
# Time settings to Adelaide and Hardware clock to UTC
ln -sf /usr/share/zoneinfo/Australia/Adelaide /etc/localtime
hwclock --systohc --utc
# Set hostname and DNS 
echo "myarch" > /etc/hostname
echo "127.0.0.1"	localhost
echo "::1"		    localhost
echo "127.0.1.1"	myarch
# Generate initramfs
mkinitcpio -P
# Set root password
echo "Set the ROOT password"
passwd
# GRUB - BIOS
pacman -S grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg
# GRUB - EFI
pacman -S grub efibootmgr
grub-install --efi--directory=/efi
grub-mkconfig -o /boot/grub/grub.cfg
# Create new user
useradd -m -G wheel -s user
sed --in-place 's/^#\s*\(%wheel\s\+ALL=(ALL)\s\+NOPASSWD:\s\+ALL\)/\1/' /etc/sudoers
echo "Set password for: user"
passwd user
# Add display manager and enable service
echo "exec gnome-session" > ~/.xinitrc
systemctl enable gdm.service
# Download tools - pycharm
#curl -L "https://download.jetbrains.com/product?code=PS&latest&distribution=linux" --output pycharm.tar.gz
git clone https://aur.archlinux.org/trizen.git && cd trizen
makepkg -sri
trizen -S pycharm-community-eap
# Download ArchISO
git clone git://projects.archlinux.org/archiso.git && cd archiso
make install && cd .. && rm -rf archiso
mkdir -p archlive/live
# Finished 
exit
reboot
EOF

# Copy post-install system cinfiguration script to new /root
cp -rfv post.sh /mnt/root
chmod a+x /mnt/root/post.sh

# Chroot into new system
echo "After chrooting into newly installed OS, please run the post.sh by executing ./post.sh"
echo "Press any key to chroot..."
read tmpvar
arch-chroot /mnt /root/post.sh

# Finish
echo "If post.sh was run succesfully, you will now have a fully working bootable Arch Linux system installed."
echo "The only thing left is to reboot into the new system."
echo "Press any key to reboot or Ctrl+C to cancel..."
read tmpvar
reboot
