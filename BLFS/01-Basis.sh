#!/bin/bash
set -euo pipefail

source ./functions.sh

echo "                                                         "
echo "========================================================="
echo "========================================================="
echo "==                   01   START                        =="
echo "==                                                     =="
echo "========================================================="
echo "========================================================="
echo "                                                         "

scripts=(

cmake
nasm
yasm
unzip
strace
gdb
lsof
pciutils
hwdata
procps-ng

)

for pkg in "${scripts[@]}"; do
    echo "========= Building $pkg =========="
    cd "$ROOT_DIR"
    source "./scripts/$pkg"
done

if swapon --show | grep -q /swapfile; then
    swapoff "/swapfile"
fi

dd if=/dev/zero of=/swapfile bs=1M count=100
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

if ! grep -q  /swapfile /etc/fstab; then
    echo "/swapfile   none    swap    sw    0   0" >> /etc/fstab
fi

echo "                                                         "
echo "========================================================="
echo "========================================================="
echo "==                   01   COMPLETE                     =="
echo "==                                                     =="
echo "========================================================="
echo "========================================================="
echo "                                                         "

