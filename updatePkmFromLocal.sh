#!/bin/bash
LFS=/home/lfs/lfsScripted
BASE=/home/tech/Git/lfsScripted
echo "updating all but etc/pkm.conf"
pushd $BASE/etc/pkm >/dev/null 2>&1
for i in *; do
    [ -d $i ] && sudo cp -vfr $i $LFS
done
popd >/dev/null 2>&1
echo "Updating pkm.sh"
pushd $BASE >/dev/null 2>&1
sudo cp -vf pkm.sh $LFS/
popd >/dev/null 2>&1
echo "Updating owner:group"
sudo chown lfs:lfs -c $LFS
echo "Done."
