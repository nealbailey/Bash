#/bin/bash
sudo mount.cifs //baileyfs01/Profiles /mnt/baileyfs01/Profiles -o username=nealosis,uid=nealosis,file_mode=0777,dir_mode=0777,credentials=/etc/samba/.cifspw
sudo rsync --archive -hW --no-compress --progress /mnt/baileyfs01/Profiles/ /mnt/md0/Profiles/
sudo umount /mnt/baileyfs01/Profiles

sudo mount.cifs //baileyfs01/Photos /mnt/baileyfs01/Photos -o username=nealosis,uid=nealosis,file_mode=0777,dir_mode=0777,credentials=/etc/samba/.cifspw
sudo rsync --archive -hW --no-compress --progress /mnt/baileyfs01/Photos/ /mnt/md0/Photos/
sudo umount /mnt/baileyfs01/Photos 

sudo mount.cifs //baileyfs01/Music2 /mnt/baileyfs01/Music2 -o username=nealosis,uid=nealosis,file_mode=0777,dir_mode=0777,credentials=/etc/samba/.cifspw
sudo rsync --archive -hW --no-compress --progress /mnt/baileyfs01/Music2/ /mnt/md0/Music2/
sudo umount /mnt/baileyfs01/Music2 

sudo mount.cifs //baileyfs01/Music /mnt/baileyfs01/Music -o username=nealosis,uid=nealosis,file_mode=0777,dir_mode=0777,credentials=/etc/samba/.cifspw
sudo rsync --archive -hW --no-compress --progress /mnt/baileyfs01/Music/ /mnt/md0/Music/
sudo umount /mnt/baileyfs01/Music

sudo mount.cifs //baileyfs01/Movies /mnt/baileyfs01/Movies -o username=nealosis,uid=nealosis,file_mode=0777,dir_mode=0777,credentials=/etc/samba/.cifspw
sudo rsync --archive -hW --no-compress --progress /mnt/baileyfs01/Movies/ /mnt/md0/Movies/
sudo umount /mnt/baileyfs01/Movies 

sudo mount.cifs //baileyfs01/Files /mnt/baileyfs01/Files -o username=nealosis,uid=nealosis,file_mode=0777,dir_mode=0777,credentials=/etc/samba/.cifspw
sudo rsync --archive -hW --no-compress --progress /mnt/baileyfs01/Files/ /mnt/md0/Files/
sudo umount /mnt/baileyfs01/Files 

sudo mount.cifs //baileyfs01/Video2 /mnt/baileyfs01/Video2 -o username=nealosis,uid=nealosis,file_mode=0777,dir_mode=0777,credentials=/etc/samba/.cifspw
sudo rsync --archive -hW --no-compress --progress /mnt/baileyfs01/Video2/ /mnt/md0/Video/
sudo umount /mnt/baileyfs01/Video2 

sudo mount.cifs //baileyfs01/Video /mnt/baileyfs01/Video -o username=nealosis,uid=nealosis,file_mode=0777,dir_mode=0777,credentials=/etc/samba/.cifspw
sudo rsync --archive -hW --no-compress --progress /mnt/baileyfs01/Video/ /mnt/md0/Video/
sudo umount /mnt/baileyfs01/Video 

sudo mount.cifs //baileyfs01/Transmission /mnt/baileyfs01/Transmission/ -o username=nealosis,uid=nealosis,file_mode=0777,dir_mode=0777,credentials=/etc/samba/.cifspw
sudo rsync --archive -hW --no-compress --progress /mnt/baileyfs01/Transmission/* /mnt/md0/Downloads/
sudo umount /mnt/baileyfs01/Transmission 








