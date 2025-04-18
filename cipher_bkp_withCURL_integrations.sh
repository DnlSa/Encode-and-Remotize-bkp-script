
#!/bin/sh
dir="/home/user/BACKUP"                       # absolute path on store this script backup
dir_md5="/home/user/md5file"                #absolute path md5file direcroty
dest_backup_path="/home/user/backuptemp"     # path for stored temporary backup
localpath="/opt/backup"                   # path where the folder with the backup is located
remotepath="<remote path for export backup >"   # path for remotize backup
name=$(date '+%Y-%m-%d')


remote_pwd="$(openssl enc -aes-256-cbc -d -salt -in "$dir/remote_pwd.enc" -pass file:$dir/key_pwd.enc)" # decrypt password for access on remote server
pass="$(openssl enc -aes-256-cbc -d -salt -in "$dir/cipher_pwd.enc" -pass file:$dir/key_pwd.enc)" # decrypt password for access on remote server

remote_ip_port='<IP ADDRESS REMOTE SERVER>:<PORT>'
remote_usr='<remote user >'

rm -rf $dir_md5/*.md5
rm -rf $dir_md5/*.txt
rm -rf $dest_backup_path/*

# configuration backup 
system_backup_filename="$(hostname)-${name}_system_settings.tar.gz"

sudo tar -cvzf $dest_backup_path/$system_backup_filename <list of file for backup>


sudo chown <USER>:<GROUP USER > $dest_backup_path/*system_settings.tar.gz

gzip -t $dest_backup_path/*system_settings.tar.gz  2>> "$dir/error_log_$name.txt"
if [ $? -ne 0 ]; then 
    echo "integrity error"
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir/error_log_$name.txt" --ftp-create-dirs -S
    exit 1 
fi 
echo "integrity test $system_backup_filename  PASSED"

# CREATE MD5 FILE
md5sum $dest_backup_path/$system_backup_filename > $dir_md5/src_${system_backup_filename}.txt #md5 system_backup
md5sum $dest_backup_path/$system_backup_filename > $dir_md5/$system_backup_filename.md5

# Compressing file + generating the md5sum

backup_file_name=$(ls -lrt "$localpath" |grep '\.tgz$'| tail -n 1  | awk '{ print $9 }')  #take bkp name (this backup create by Gui , daily once at time 2:15 a.m. )
backup_file_name_exp="$(hostname)_$backup_file_name"

echo "control----------------------------------- $backup_file_name"
if [[ "$backup_file_name" != *"$(hostname)"* ]]; then 
        mv "$localpath/$backup_file_name"  "$localpath/$backup_file_name_exp"
        backup_file_name="$backup_file_name_exp"       
fi


gzip -t  $localpath/$backup_file_name  2>> "$dir/error_log_$name.txt"
if [ $? -ne 0 ]; then 
    echo "integrity error"
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir/error_log_$name.txt" --ftp-create-dirs -S
    exit 1 
fi 
echo "integrity test $backup_file_name    PASSED"

md5sum $localpath/$backup_file_name > $dir_md5/src_${backup_file_name}.txt
md5sum $localpath/$backup_file_name > $dir_md5/${backup_file_name}.md5


#openssl algotihm
dest_h_name='DESTINATION HOST NAME CREATED ON CIPHERTRUST '
ip_cipher_rm='<CIPHERTRUST IP 1>'
ip_cipher_mi='<CIPHERTRUST IP 2>'
ip_cipher_roz='<CIPHERTRUST IP 3>'

port=<PORT FOR ACCESS TO CIPHERTRUST>
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
    established=0 #failed to connect
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
        openssl enc -e -aes256 -in "$localpath/$backup_file_name" -out "$localpath/$backup_file_name.aes-256-cbc" -pass pass:$cat_key
        openssl enc -e -aes256 -in "$dest_backup_path/$system_backup_filename" -out "$dest_backup_path/$system_backup_filename.aes-256-cbc" -pass pass:$cat_key
        md5sum $localpath/${backup_file_name}.aes-256-cbc > $dir_md5/${backup_file_name}.aes-256-cbc.md5
        md5sum $dest_backup_path/${system_backup_filename}.aes-256-cbc > $dir_md5/${system_backup_filename}.aes-256-cbc.md5
        list_data_file=("$localpath/$backup_file_name.aes-256-cbc"  "$dir_md5/${backup_file_name}.aes-256-cbc.md5" "$dest_backup_path/$system_backup_filename.aes-256-cbc" "$dir_md5/${system_backup_filename}.aes-256-cbc.md5")
    else
        list_data_file=("$localpath/$backup_file_name" "$dir_md5/${backup_file_name}.md5" "$dest_backup_path/$system_backup_filename" "$dir_md5/${system_backup_filename}.md5")
    fi
fi


#######################################################################  DATA CONTROL  $localpath/$backup_file_name.aes-256-cbc #############################


#control cipher backup 
openssl enc -d -aes256 -in "$localpath/$backup_file_name.aes-256-cbc" -out "$localpath/decode_$backup_file_name" -pass pass:"$cat_key" 2> "$dir/error_log_$name.txt"
if [ $? -ne 0 ]; then
    echo "error to decypt - DATA BACKUP"
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir_md5/src_${backup_file_name}.txt" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir_md5/src_${system_backup_filename}.txt" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$localpath/$backup_file_name" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dest_backup_path/$system_backup_filename" --ftp-create-dirs  -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir/error_log_$name.txt" --ftp-create-dirs  -S
    rm -f  "$localpath/decode_$backup_file_name"
    exit 1 
fi 
echo  "decrypt  DATA backup PASSED"


decode_md5=$(md5sum "$localpath/decode_$backup_file_name" | awk '{print $1}')
src_md5=$(cat $dir_md5/src_${backup_file_name}.txt | awk '{print $1}')
if [ "$decode_md5" != "$src_md5" ]; then
    echo "error to match file post decypt - DATA BACKUP"
    echo "md5 decode is not equal than source md5 $decode_md5 NOT EQUAL $src_md5" > "$dir/error_log_$name.txt"
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir_md5/src_${backup_file_name}.txt" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir_md5/src_${system_backup_filename}.txt" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$localpath/$backup_file_name" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dest_backup_path/$system_backup_filename" --ftp-create-dirs  -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir/error_log_$name.txt" --ftp-create-dirs  -S
    rm -f  "$localpath/decode_$backup_file_name"
    exit 1 
fi 
echo "match MD5 file-decoded and MD5 source-file for $backup_file_name PASSED"

rm -f  "$localpath/decode_$backup_file_name"


#######################################################################  SYSTEM CONTROL $dest_backup_path/$system_backup_filename.aes-256-cbc #############################

openssl enc -d -aes256 -in "$dest_backup_path/$system_backup_filename.aes-256-cbc" -out "$dest_backup_path/decode_${system_backup_filename}" -pass pass:"$cat_key" 2> "$dir/error_log_$name.txt"
if [ $? -ne 0 ]; then
    echo "error to decypt - SYSTEM BACKUP"
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir_md5/src_${backup_file_name}.txt" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir_md5/src_${system_backup_filename}.txt" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$localpath/$backup_file_name" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dest_backup_path/$system_backup_filename" --ftp-create-dirs  -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir/error_log_$name.txt" --ftp-create-dirs  -S
    rm -f  "$dest_backup_path/decode_${system_backup_filename}"
    exit 1 
fi 
echo  "decrypt SYSTEM backup PASSED"



decode_md5=$(md5sum "$dest_backup_path/decode_${system_backup_filename}" | awk '{print $1}')
src_md5=$(cat "$dir_md5/src_${system_backup_filename}.txt" | awk '{print $1}')
if [ "$decode_md5" != "$src_md5" ]; then
    echo "error to match file post decypt - SYSTEM BACKUP"
    echo "md5 decode is not equal than source md5 $decode_md5 NOT EQUAL $src_md5" > "$dir/error_log_$name.txt"
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir_md5/src_${backup_file_name}.txt" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir_md5/src_${system_backup_filename}.txt" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$localpath/$backup_file_name" --ftp-create-dirs -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dest_backup_path/$system_backup_filename" --ftp-create-dirs  -S
    curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir/error_log_$name.txt" --ftp-create-dirs  -S
    rm -f  "$localpath/decode_$backup_file_name"
    exit 1 
fi 
echo "match MD5 file-decoded and MD5 source-file ${system_backup_filename}       PASSED"

rm -f "$localpath/decode_$backup_file_name"
rm -f "$dir/error_log_$name.txt"


#upload data files
for string in "${list_data_file[@]}" ;do
                curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$string" --ftp-create-dirs -S
done

#upload system files 
for string in "${list_system_file[@]}" ;do
                curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$string" --ftp-create-dirs -S
done

 #md5 source in all case are done 
curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir_md5/src_${backup_file_name}.txt" --ftp-create-dirs -S
curl  -k "sftp://$remote_ip_port$remotepath" --user "$remote_usr:$remote_pwd" -T "$dir_md5/src_${system_backup_filename}.txt" --ftp-create-dirs -S
