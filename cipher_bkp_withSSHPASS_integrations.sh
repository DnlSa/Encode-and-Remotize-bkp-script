#!/bin/bash


echo " init Backup"

BKP_PATH="/home/user/backuptemp"
BACKUP_PATH="/home/user/BACKUP"
dat=`date '+%d_%m_%Y_%HH%MM%SS'`
remotepath="<remote path for export backup >"   # path for remotize backup
dir="/home/user/BACKUP"
name_site="<name_site>"

key=`tail -1 /etc/ims/cmkeys | awk -F'=' '{print $1}'`
value=`tail -1 /etc/ims/cmkeys | awk -F'=' '{print $2}'`
token="token#\$#$key"
timestamp=`date +%s`
passcode="$value#\$#$timestamp"
remote_ip_port='<IP ADDRESS REMOTE SERVER>'
remote_usr='<remote user >'

if [ $# == 0 ];then
  echo "No backup path given. Taking backup in default location - $BKP_PATH"
else
  echo "Backup path : $1"
  BKP_PATH=$1
fi


if  echo "$RESPONSE" | grep -q "$STATUS" ; then
  echo "Backup Successful";
  execCmd "tar -P -cvf $BKP_PATH/backup.dmp $BACKUP_PATH/backuprepo.dmp $BACKUP_PATH/AllDns_Backup.tar.gz" 2>> "$BACKUP_PATH/error_log_${dat}.txt"
  if [ $? -eq 0 ];then
    logmsg "Successfully compressed the ${BKP_PATH}/backup.dmp"
  else
    logerr "Failed to compressed the ${BKP_PATH}/backup.dmp"
    sshpass -p "$remote_pwd" sftp  -q sftp_nokia@10.133.238.31 << EOF
put $BACKUP_PATH/error_log_${dat}.txt  $remotepath #send md5 source
EOF
    exit 1
  fi
  execCmd "mv -f $BKP_PATH/backup.dmp $BKP_PATH/backuprepo.dmp"
  if [ $? -eq 0 ];then
    logmsg "Successfully renamed from $BKP_PATH/backup.dmp to ${BKP_PATH}/backuprepo.dmp"
  else
    logerr "Failed to rename from $BKP_PATH/backup.dmp to  ${BKP_PATH}/backuprepo.dmp"
    exit 1
  fi
else
  echo "Backup Failed!";
  exit 1
fi

mv $BACKUP_PATH/AllDns_Backup.tar.gz $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}.tar.gz

gzip -t $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}.tar.gz 2>> "$BACKUP_PATH/error_log_${dat}.txt"
if [ $? -ne 0 ]; then
    echo "compress_error" > $BACKUP_PATH/error_log_${dat}.txt
    sshpass -p "$remote_pwd" sftp  -q $remote_usr:$remote_pwd << EOF
put $BACKUP_PATH/error_log_${dat}.txt  $remotepath #send md5 source
EOF
    exit 1
fi
echo "compress_tar.gz  PASSED"

mv $BACKUP_PATH/backuprepo.dmp $BACKUP_PATH/${name_site}_backuprepo_${dat}.dmp
md5sum $BACKUP_PATH/${name_site}_backuprepo_${dat}.dmp > $BACKUP_PATH/src_${name_site}_backuprepo_"${dat}".txt
md5sum $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}.tar.gz > $BACKUP_PATH/src_${name_site}_AllDns_Backup_"${dat}".txt


remote_pwd="$(openssl enc -aes-256-cbc -d -salt -in "$dir/remote_pwd.enc" -pass file:$dir/key_pwd.enc)"
pass="$(openssl enc -aes-256-cbc -d -salt -in "$dir/cipher_pwd.enc" -pass file:$dir/key_pwd.enc)"


dest_h_name='DESTINATION HOST NAME CREATED ON CIPHERTRUST '
ip_cipher_rm='<CIPHERTRUST IP 1>'
ip_cipher_mi='<CIPHERTRUST IP 2>'
ip_cipher_roz='<CIPHERTRUST IP 3>'

port=9000
key_path="$dir/key.txt"
established=0
cipheruser="<insert here ciphertrust user >"

test_connection() {
    timeout 5 openssl s_client -connect "$1:$2" </dev/null 2>/dev/null | grep -q "CONNECTED" #view if port take on extern function if not pass second arguments 
    return $? #return state of previeus command 
}

if test_connection "$ip_cipher_rm" "$port"; then
    ip_cipher="$ip_cipher_rm"
    established=1
elif test_connection "$ip_cipher_mi" "$port"; then
       ip_cipher="$ip_cipher_mi"
       established=1
elif test_connection "$ip_cipher_roz" "$port"; then
       ip_cipher="$ip_cipher_roz"
       established=1
else 
    established=0 
fi

if [ "$established" -eq 1 ]; then 
    ip_list=("$ip_cipher_rm" "$ip_cipher_mi" "$ip_cipher_roz")
    for ip in "${ip_list[@]}"; do
        echo "$ip"
        (echo "<VersionRequest><MessageVersion>1.0</MessageVersion><ID>1</ID><VersionList><Version>2.9</Version></VersionList></VersionRequest><AuthRequest><ID>2</ID><User>"$cipheruser"</User><Passwd>"$pass"</Passwd></AuthRequest><KeyExportRequest><ID>2</ID><KeyName>"$dest_h_name"</KeyName></KeyExportRequest>"; sleep 5) | openssl s_client -connect "$ip:$port" | grep -Po "<KeyData>(.*?)<\/KeyData>" | tail -c +10 | head -c -11 > "$key_path"
        if [[ -s "$key_path" ]]; then
           break
        fi
    done 
    cat_key=$(cat "$key_path")
    num_char=$(ls -larth "$key_path"| awk '{print $5}')
    rm -f "$key_path"
    if  [ "$num_char" -ne 0 ] ; then        
        openssl enc -e -aes256 -in $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}.tar.gz -out $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}.tar.gz.cbc -pass pass:$cat_key
        openssl enc -e -aes256 -in $BACKUP_PATH/${name_site}_backuprepo_${dat}.dmp -out $BACKUP_PATH/${name_site}_backuprepo_${dat}.dmp.cbc -pass pass:$cat_key
        md5sum $BACKUP_PATH/${name_site}_backuprepo_${dat}.dmp.cbc > $BACKUP_PATH/${name_site}_backuprepo_${dat}.dmp.cbc.md5
        md5sum $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}.tar.gz.cbc > $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}.tar.gz.cbc.md5
        list_put_file=("${name_site}_AllDns_Backup_${dat}.tar.gz.cbc" "${name_site}_backuprepo_${dat}.dmp.cbc" "${name_site}_AllDns_Backup_${dat}.tar.gz.cbc.md5" "${name_site}_backuprepo_${dat}.dmp.cbc.md5" "src_${name_site}_backuprepo_${dat}.txt" "src_${name_site}_AllDns_Backup_"${dat}".txt")
    else
        list_put_file=("${name_site}_AllDns_Backup_${dat}.tar.gz" "${name_site}_backuprepo_${dat}.dmp" "src_${name_site}_backuprepo_${dat}.txt" "src_${name_site}_AllDns_Backup_"${dat}".txt")
    fi
fi

###############################################     decrypt $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}.tar.gz.cbc #############################################

#control cipher backup DMP
openssl enc -d -aes256 -in "$BACKUP_PATH/${name_site}_AllDns_Backup_${dat}.tar.gz.cbc" -out "$BACKUP_PATH/${name_site}_AllDns_Backup_${dat}_decode.tar.gz" -pass pass:"$cat_key" 2> "$BACKUP_PATH/error_log_${dat}.txt"
if [ $? -ne 0 ]; then
    echo "error to decypt"
    list_put_file=("${name_site}_AllDns_Backup_${dat}.tar.gz" "${name_site}_backuprepo_${dat}.dmp" "src_${name_site}_backuprepo_${dat}.txt" "src_${name_site}_AllDns_Backup_"${dat}".txt" "error_log_${dat}.txt")
    sshpass -p "$remote_pwd" sftp -q $remote_usr:$remote_pwd << EOF
        $(for string in "${list_put_file[@]}" ;do
            echo  "put \"$BACKUP_PATH/$string\" \"$remotepath\"" 
        done)
EOF
    rm -f $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}_decode.tar.gz
    exit 1 
fi 
echo  "decrypt ${name_site}_AllDns_Backup_${dat}.tar.gz      PASSED"

decode_md5=$(md5sum "$BACKUP_PATH/${name_site}_AllDns_Backup_${dat}_decode.tar.gz" | awk '{print $1}')
src_md5=$(cat $BACKUP_PATH/src_${name_site}_AllDns_Backup_${dat}.txt | awk '{print $1}')
if [ "$decode_md5" != "$src_md5" ]; then
    echo "md5 decode is not equal than source md5 $decode_md5 NOT EQUAL $src_md5  for ${name_site}_AllDns_Backup_${dat}.tar.gz" >> "$BACKUP_PATH/error_log_${dat}.txt"
    list_put_file=("${name_site}_AllDns_Backup_${dat}.tar.gz" "${name_site}_backuprepo_${dat}.dmp" "src_${name_site}_backuprepo_${dat}.txt" "src_${name_site}_AllDns_Backup_"${dat}".txt" "error_log_${dat}.txt")
    sshpass -p "$remote_pwd" sftp -q $remote_usr:$remote_pwd << EOF
        $(for string in "${list_put_file[@]}" ;do
                echo  "put \"$BACKUP_PATH/$string\" \"$remotepath\"" 
        done)
EOF
    rm -f $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}_decode.tar.gz
    exit 1
fi 
echo "match MD5 file-decrypted and MD5 source-file  for ${name_site}_AllDns_Backup_${dat}.tar.gz        PASSED"

rm -f $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}_decode.tar.gz

#################################################### decrypt $BACKUP_PATH/${name_site}_backuprepo_${dat}.dmp.cbc ####################################


#control cipher backup DMP
openssl enc -d -aes256 -in "$BACKUP_PATH/${name_site}_backuprepo_${dat}.dmp.cbc" -out "$BACKUP_PATH/${name_site}_backuprepo_${dat}_decode.dmp" -pass pass:"$cat_key" 2> "$BACKUP_PATH/error_log_${dat}.txt"
if [ $? -ne 0 ]; then
    echo "error to decypt"
    list_put_file=("${name_site}_AllDns_Backup_${dat}.tar.gz" "${name_site}_backuprepo_${dat}.dmp" "src_${name_site}_backuprepo_${dat}.txt" "src_${name_site}_AllDns_Backup_"${dat}".txt" "error_log_${dat}.txt")
    sshpass -p "$remote_pwd" sftp -q $remote_usr:$remote_pwd << EOF
        $(for string in "${list_put_file[@]}" ;do
            echo  "put \"$BACKUP_PATH/$string\" \"$remotepath\"" 
        done)
EOF
    rm -f $BACKUP_PATH/${name_site}_backuprepo_${dat}_decode.dmp
    exit 1 
fi 
echo  "decrypt ${name_site}_backuprepo_${dat}.dmp      PASSED"

decode_md5=$(md5sum "$BACKUP_PATH/${name_site}_backuprepo_${dat}_decode.dmp" | awk '{print $1}')
src_md5=$(cat "$BACKUP_PATH/src_${name_site}_backuprepo_"${dat}".txt" | awk '{print $1}')
if [ "$decode_md5" != "$src_md5" ]; then
    echo "md5 $BACKUP_PATH/${name_site}_backuprepo_${dat}_decode.dmp NOT PASSED"
    echo "md5 decode is not equal than source md5 $decode_md5 NOT EQUAL $src_md5 for /${name_site}_backuprepo_${dat}_decode.dmp " >> "$BACKUP_PATH/error_log_${dat}.txt"
    list_put_file=("${name_site}_AllDns_Backup_${dat}.tar.gz" "${name_site}_backuprepo_${dat}.dmp" "src_${name_site}_backuprepo_${dat}.txt" "src_${name_site}_AllDns_Backup_"${dat}".txt" "error_log_${dat}.txt")
    sshpass -p "$remote_pwd" sftp -q $remote_usr:$remote_pwd << EOF
        $(for string in "${list_put_file[@]}" ;do
                echo  "put \"$BACKUP_PATH/$string\" \"$remotepath\"" 
        done)
EOF
    rm -f $BACKUP_PATH/${name_site}_backuprepo_${dat}_decode.dmp
    exit 1
fi 
echo "match MD5 file-decrypted and MD5 source-file  for ${name_site}_backuprepo_${dat}.dmp        PASSED"

####################################################################################################################

rm -f $BACKUP_PATH/${name_site}_backuprepo_${dat}_decode.dmp
rm -f $BACKUP_PATH/${name_site}_AllDns_Backup_${dat}_decode.tar.gz
rm -f $BACKUP_PATH/error_log_${dat}.txt


sshpass -p "$remote_pwd" sftp -q $remote_usr:$remote_pwd << EOF
        $(for string in "${list_put_file[@]}" ;do
                echo  "put \"$BACKUP_PATH/$string\" \"$remotepath\"" 
        done)
EOF
