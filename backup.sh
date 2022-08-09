#!/bin/bash
#RCART.CC Universal Backup Script
#Version: 1.0
#Latest Update: 4-7-22
#----------------------------------#
#Let's Define Some Variables
#----------------------------------#
date=$(date +'%H:%M-%m-%d-%Y')
datetime=$(date +'%m-%d-%Y')
datemin=$(date +'%H:%M-%m') 
#Discord Alert Variables
#The webhook URL
webhook=""
#The avatar the webhook should use
avat=""
#The username of the webhook
usern="Backup script"
#----------------------------------#
declare -a sources=("/etc/pterodactyl/" "/root/" "/var/lib/pterodactyl/volumes/")
#----------------------------------#
#Backup Location Variables
logloc="/var/log/backups"
mountloc="/mnt/nfs/"
retention="3"
#NFS Mount Variables
mountcommand="mount -v -t nfs 10.66.66.66:/mnt/media/NX01 /mnt/nfs -o fsc"
#----------------------------------#
#Declare Dependencies 
declare -a packs=("ncdu" "bc" "pigz" "jq" "git")
#----------------------------------#
#Time to run
initlog() {
    if [ -f $logloc/backuplog-$date.txt ]; then
    echo "This script has already ran today, please verify everything is working properly."
    elif [ ! -d $logloc ]; then
    mkdir $logloc
    touch $logloc/backuplog-$date.txt
    else
    touch $logloc/backuplog-$date.txt
    fi
 }
log () {
    local LOG_LEVEL=$1
    shift
    MSG=$@
    if [[ $LOG_LEVEL -eq "ERROR" ]] || $VERBOSE
    then
    echo [$datetime] [$datemin] $(hostname) $(ps aux | awk {'print $2,$11'}  | grep $$) ${LOG_LEVEL} ${MSG} >> $logloc/backuplog-$date.txt
    fi
 }
pmc() {
    #if which yum &>/dev/null; then
        #echo "Yum detected, using yum for install."
        #pm=yum
    #fi
    if which apt &>/dev/null; then
        echo "Your packaged manager has been detected as APT."
        pm=apt
        log INFO "Package manager has been detected as $pm"
    fi
    if which dnf &>/dev/null; then
        echo "Your packaged manager has been detected as DNF."
        pm=dnf
        log INFO "Package manager has been detected as $pm"
    fi
    if [ -z "${pm}" ]; then
        echo "Package manager could not be found, aborting..."
        log ERROR "Package manager could not be detected, please ensure the system is compatible!"
    fi
    }
loadpacks() {
    echo "==============================="
    echo "Dependency Check:"
    echo ""
    for nservice in "${packs[@]}"; do
    log INFO "Checking if $nservice is installed..."
    checkpack
    done
    #Check to see if discord.sh is installed
    if [ -d "/root/scripts/discord.sh" ]; then
        echo -e "\xE2\x9C\x94 Discord.sh installed"
        log INFO "Discord.sh installed"
    else
        echo -e "\xE2\x9D\x8C Discord.sh not installed, installing..."
        git clone https://github.com/ChaoticWeg/discord.sh.git /root/scripts/discord.sh &> /dev/null && sleep 2 && clear && loadpacks && log INFO "Discord.Sh cloned from github"
    fi
    }
checkpack() {
    if which $nservice &>/dev/null; then
        echo -e "\xE2\x9C\x94 $nservice installed"
        log INFO "$nservice installed"
    else
        log INFO "$nservice not installed, installing..."
        echo -e "\xE2\x9D\x8C $nservice not installed, installing..." && $pm install $nservice -y >/dev/null && checkpack && log INFO "$nservice Installed"
    fi
    
    }
discordlog() {
bash /root/scripts/discord.sh/discord.sh --webhook-url="$webhook" \
 --username "$usern" \
 --avatar "$avat" \
 --title "$(hostname)" \
 --description "$desc" \
 --field "$fieldname $field1" \
 --field "$fieldname2 $field2" \
 --color "$setcolor" \
 --timestamp
}
discordfilesend() {
  bash /root/scripts/discord.sh/discord.sh --webhook-url="$webhook" \
  --username "$usern" \
  --avatar "$avat" \
  --file "$discordfile"
 }
mountNFS () {
    if [ -f $mountloc/nfs.txt ]; then
    echo "NFS server is mounted but unable to write."
    log ERROR "NFS server has been detected as mounted but is unable to write. Please check permissions."
    else
    echo "NFS server may not be mounted, attempting to remount."
    log NOTICE "NFS server may not be mounted, attempting to remount."
    log INFO "Unmounting NFS server" && umount -f /mnt/nfs
    $mountcommand && chkmount || log ERROR "NFS server could not be remounted! Manual intervention required!"
    echo "NFS server could not be remounted! Manual intervention required!"
    exit
    fi
}
chkmount () {
    if [ -f $mountloc/nfs.txt ]; then
    echo $date > $mountloc/nfs.txt
    fi
    if grep -qs $date "$mountloc/nfs.txt"; then
    echo "NFS Working"
    export nfsStatus="mounted"
    log INFO "NFS has been detected as mounted." 
    else
    log ERROR "NFS is either not mounted or is unable to read/write. Please investigate!"
    echo "NFS has been detected as ummounted!"
    mountNFS
    fi
}
createFolder() {
    if [ ! -d $mountloc$(hostname) ]; then
        mkdir -p $mountloc$(hostname)
        log INFO "$mountloc$(hostname) has been created"
        if [ ! -d $mountloc$(hostname)/$datetime ]; then
        mkdir -p $mountloc$(hostname)/$datetime
        log INFO "$mountloc$(hostname)/$datetime has been created"
        else 
        echo "Directory Exists"
        log INFO "$mountloc$(hostname)/$datetime already exists"
        fi
    else
        if [ ! -d $mountloc$(hostname)/$datetime ]; then
        mkdir -p $mountloc$(hostname)/$datetime
        else 
        echo "Directory Exists"
        log INFO "$mountloc$(hostname)/$datetime already exists"
        fi
    fi
    backpath=$mountloc$(hostname)/$datetime
}
pteroBackup() {
    cd /var/lib/pterodactyl/volumes/
    for volume in * ; 
    do
    echo "$volume"
    currsize=$(du -sh $volume | cut -f1)
    desc="**Starting Backup**" && fieldname="Server:;$volume"
    fieldname2="Size:;$currsize" && setcolor="0xF2E409"
    discordlog
    log INFO "Starting Compression for $volume $currsize"
    tar cf - $volume | pigz -9 -p 2 > $backpath/$volume.tar.gz
    compresssize=$(du -sh $backpath/$volume.tar.gz | cut -f1)
    desc="**Finished Backup**" && fieldname="Server:;$volume"
    fieldname2="Compressed Size:;$compresssize" && setcolor="0x01B031"
    log INFO "Compression Finished for $volume $compresssize"
    discordlog

    done

}
mysqlBackup() {
cd $backpath
log INFO "Starting MySQL Backup"
mysql -u root -p -e 'SELECT table_schema AS "Database", SUM(data_length + index_length) / 1024 / 1024 AS "Size (MB)" FROM information_schema.TABLES GROUP BY table_schema;' | sort -nk2 | grep -v "(MB)" | awk {'print $1'} | while read dbname; do
log INFO "Dumping $dbname to file"
currsize=$(du -sh "/var/lib/mysql/$dbname" | cut -f1)
desc="**MySQL Dump**" && fieldname="Database:;$dbname"
fieldname2="Size:;$currsize" && setcolor="0xF2E409"
discordlog
mysqldump --skip-lock-tables "$dbname" > "$dbname.sql"
tar cf - "$dbname.sql" | pigz -9 -p 2 > "$backpath/$dbname-sql.tar.gz"
compresssize=$(du -sh "$dbname-sql.tar.gz" | cut -f1)
desc="**Finished MySQL Backup**" && fieldname="Database:;$dbname"
fieldname2="Compressed Size:;$compresssize" && setcolor="0x01B031"
discordlog
log INFO "Compression Finished for $dbname $compresssize"
rm -rf "$dbname.sql"
#Avoid rate limit from discord
sleep 2  
done
log INFO "MySQL backup complete"
}



Backup() {
    ts=$(date +%s)
    for runningbackup in "${sources[@]}"; do
    echo $runningbackup
    if [ "$runningbackup" = "/var/lib/pterodactyl/volumes/" ];
    then 
    pteroBackup
    else
    cd $runningbackup
    currdirectory=$(basename "$PWD")
    currsize=$(du -sh $runningbackup | cut -f1 )
    log INFO "Backup Started on $currdirectory $currsize"
    echo $currsize
    desc="**Starting Backup**" && fieldname="Directory:;$currdirectory"
    fieldname2="Size:;$currsize" && setcolor="0xF2E409"
    discordlog
    tar cf - * | pigz -9 -p 2 > $backpath/$currdirectory.tar.gz
    compresssize=$(du -sh $backpath/$currdirectory.tar.gz | cut -f1)
    log INFO "Finished Backup for $currdirectory $compresssize"
    desc="**Finished Backup**" && fieldname="Directory:;$currdirectory"
    fieldname2="Compressed Size:;$compresssize" && setcolor="0x01B031"
    discordlog
    fi
    done 
    td=$(date +%s)
    timetaken=$(echo "($td-$ts)/60" | bc)
}
Cleanup() {
    log INFO "Cleaning up files older than $retention days."
    find $mountloc$(hostname) -mtime +3 -exec ls -lah {} \; >> $logloc/backuplog-$date.txt
    find $mountloc$(hostname) -mtime +3 -exec rm -rf {} \; >> $logloc/backuplog-$date.txt
    find $mountloc$(hostname) -empty -type d -delete >> $logloc/backuplog-$date.txt
}
logExport() {
    log INFO "Backups Completed in $timetaken minutes for $(hostname)"
    desc="**Backups Completed**"
    setcolor="0x09C8EB"
    desc="**Backups Completed**" && fieldname="Time Taken:;$timetaken (in minutes)"
    fieldname2="Completed;Completed" && setcolor="0x01B031"
    discordlog
    discordfile="$logloc/backuplog-$date.txt" 
    discordfilesend
}
#----------------------------------#
initlog
pmc
loadpacks
echo "==============================="
chkmount
createFolder
Backup
mysqlBackup
Cleanup
logExport
echo "Completed"
#----------------------------------#
