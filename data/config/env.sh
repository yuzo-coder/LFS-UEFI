#Configuration file for scripts to run on host as root

PARTITION="nbd0p2"

PWD=`pwd`
LFS="$PWD/builddir"
MAKEFLAGS="-j`nproc`"

echo $LFS

export PWD LFS MAKEFLAGS
