#/bin/bash
sudo rsync --av -hW --no-compress --modify-window=1 --no-owner --no-group --no-perms --progress  /mnt/md0/Profiles/ /mnt/seagate22tb/Profiles/ #2>/dev/null
sudo rsync --av -hW --no-compress --modify-window=1 --no-owner --no-group --no-perms --progress  /mnt/md0/Photos/ /mnt/seagate22tb/Photos/ #2>/dev/null
sudo rsync --av -hW --no-compress --modify-window=1 --no-owner --no-group --no-perms --progress  /mnt/md0/Music2/ /mnt/seagate22tb/Music2/ #2>/dev/null
sudo rsync --av -hW --no-compress --modify-window=1 --no-owner --no-group --no-perms --progress  /mnt/md0/Music/ /mnt/seagate22tb/Music/ #2>/dev/null
sudo rsync --av -hW --no-compress --modify-window=1 --no-owner --no-group --no-perms --progress  /mnt/md0/Movies/ /mnt/seagate22tb/Movies/ #2>/dev/null
sudo rsync --av -hW --no-compress --modify-window=1 --no-owner --no-group --no-perms --progress  /mnt/md0/Files/ /mnt/seagate22tb/Files/ #2>/dev/null
sudo rsync --av -hW --no-compress --modify-window=1 --no-owner --no-group --no-perms --progress  /mnt/md0/Video/ /mnt/seagate22tb/Video/ #2>/dev/null
