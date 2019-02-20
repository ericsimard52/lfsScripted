#!/bin/bash
sudo umount -v /mnt/lfs/{boot,home}
sudo rmdir -v /mnt/lfs/{boot,home}
sudo rm -fr /mnt/lfs/tools
sudo umount /mnt/lfs
sudo userdel lfs
sudo groupdel lfs
sudo rm -fr /home/lfs
