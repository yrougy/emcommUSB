#!/bin/bash
# Fortement inspiré de https://willhaley.com/blog/custom-debian-live-environment/#create-bootable-usb

echo ATTENTION CE SCRIPT EST DANGEREUX ET PEUT DÉTRUIRE VOTRE MACHINE
echo APPUYEZ SUR ENTRÉE POUR CONTINUER OU CTRL-C POUR ARRÊTER
read A
echo On vérifie que ce qui est nécessaire est installé sur la machine
sudo apt install debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools

echo '########################################'
echo maintenant on crée l'arborescence de base pour le liveUSB'
# TODO: test d'existence et d'écrasement
mkdir $HOME/LIVE_BOOT
sudo debootstrap --variant=minbase disco $HOME/LIVE_BOOT/chroot 
cat << EOF > $HOME/LIVE_BOOT/chroot/installer.sh
echo "emcommfr-usb" > /etc/hostname
echo 'deb http://archive.ubuntu.com/ubuntu disco universe' >> /etc/apt/sources.list

apt update
apt install -y apt-utils
apt install -y --no-install-recommends linux-image-generic live-boot systemd-sysv network-manager net-tools wireless-tools wpagui curl openssh-client blackbox xserver-xorg-core xserver-xorg xinit xterm nano
apt-get clean
passwd root
exit
EOF

chmod +x $HOME/LIVE_BOOT/chroot/installer.sh

echo on construit maintenant la structure du système

# TODO: faire un fichier de log
chroot $HOME/LIVE_BOOT/chroot /installer.sh 
rm $HOME/LIVE_BOOT/chroot/installer.sh

echo '############################################################'
echo Maintenant on va construire la clé

# Création des répertoires
mkdir -p $HOME/LIVE_BOOT/{scratch,image/live}

# On comprime l'arborescence dans un squashfs pour le liveUSB
sudo mksquashfs $HOME/LIVE_BOOT/chroot $HOME/LIVE_BOOT/image/live/filesystem.squashfs -e boot

# On copie le noyau et le ramdisk initial de l'arborescence dans le liveUSB
cp $HOME/LIVE_BOOT/chroot/boot/vmlinuz-* $HOME/LIVE_BOOT/image/vmlinuz 
cp $HOME/LIVE_BOOT/chroot/boot/initrd.img-* $HOME/LIVE_BOOT/image/initrd

# On crée un fichier de boot GRUB fonctionnel
cat <<'EOF' >$HOME/LIVE_BOOT/scratch/grub.cfg

search --set=root --file /EMCOMMUSB

insmod all_video

set default="0"
set timeout=30

menuentry "Debian Live" {
    linux /vmlinuz boot=live quiet nomodeset
    initrd /initrd
}
EOF

# On crée un fichier qui va permettre à GRUB de trouver le périphérique de boot
touch  $HOME/LIVE_BOOT/image/EMCOMMUSB

# Maintenant on crée la clé

echo le périphérique de la clé est /dev/sdb. Faites ctrl-c maintenant si ce n\'est pas le cas
read A

export disk=/dev/sdb
sudo mkdir -p /mnt/{usb,efi}

# On utilise parted pour partitionner la clé en mode hybride MBR/UEFI
sudo parted --script $disk \
    mklabel gpt \
    mkpart primary fat32 2048s 4095s \
        name 1 BIOS \
        set 1 bios_grub on \
    mkpart ESP fat32 4096s 413695s \
        name 2 EFI \
        set 2 esp on \
    mkpart primary fat32 413696s 100% \
        name 3 LINUX \
        set 3 msftdata on

# On partitionne avec gdisk ( redondant ??)
sudo gdisk $disk << EOF
r     # recovery and transformation options
h     # make hybrid MBR
1 2 3 # partition numbers for hybrid MBR
N     # do not place EFI GPT (0xEE) partition first in MBR
EF    # MBR hex code
N     # do not set bootable flag
EF    # MBR hex code
N     # do not set bootable flag
83    # MBR hex code
Y     # set the bootable flag
x     # extra functionality menu
h     # recompute CHS values in protective/hybrid MBR
w     # write table to disk and exit
Y     # confirm changes
EOF

# On formate les partitions data et UEFI
sudo mkfs.vfat -F32 ${disk}2 
sudo mkfs.vfat -F32 ${disk}3

# On monte les partitions pour pouvoir y mettre les données
sudo mount ${disk}2 /mnt/efi 
sudo mount ${disk}3 /mnt/usb

# On install GRUB
sudo grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi \
    --boot-directory=/mnt/usb/boot \
    --removable \
    --recheck
sudo grub-install \
    --target=i386-pc \
    --boot-directory=/mnt/usb/boot \
    --recheck \
    $disk

# On crée les répertoires du liveUSB
sudo mkdir -p /mnt/usb/{boot/grub,live}

# On copie le contenu sur la clé
sudo cp -r $HOME/LIVE_BOOT/image/* /mnt/usb/
# On copie grub.cfg sur la clé
sudo cp \
    $HOME/LIVE_BOOT/scratch/grub.cfg \
    /mnt/usb/boot/grub/grub.cfg

# On a fini, on éjecte la clé

sudo umount /mnt/{usb,efi}


