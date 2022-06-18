#!/bin/bash

#deafult and fixe variables
username=admin
password=HyperInteractive
import_privileges=yes
list_of_tables_filename=list_of_tables.txt
list_of_dashboards_filename=list_of_dashboards.txt
list_of_users_filename=list_of_users.txt
list_of_views_filename=list_of_views.txt

function show_usage_and_exit()  {
  echo "backup_database.sh backup|restore --database=database_name --dumpfile=dump_file --dumpdir=tempdir --forcedb --noprivs [--user=username] [--password=pwd] "
  exit $1
}

function checkDatabaseExists() {
  database_exists=$(echo "show databases;" | omnisql -u $username -p $password -q | egrep "^$database_to_backup\|$username" | cut -f 1 -d '|')
  if [ "$database_exists" == "" ]; then
    echo "Error: connecting to the database.
    Check you username and password are correct and the database "$database_to_backup" exists. existing";
    cleanupBackupDir
    exit -1
  fi;
}

function checkUsersExist() {
  tar xf $backup_file -C $backup_dir $list_of_users_filename
  for i in $(cat $list_of_users_filename)
  do
    if [ "$i" != "admin" ]; then 
      echo "show user details "$i | omnisql -p HyperInteractive -q  2>/dev/null >/dev/null
      if [ $? == 0 ]; then
        cleanupBackupDir
        echo "Error: user "$i" doesn't exists in the target database. Exiting"
        exit -1
      fi;
    fi;
  done;
}

function cleanupBackupDir() {
  rm -Rf $backup_dir
}

function createAndCheckBackupDir() {
  mkdir $backup_dir
  if [ $? != 0 ]; then
    echo "Error: cannot create the temporary directory ("$backup_dir") for the "$action". Exiting"
    exit -1
  fi;
  if [ "$action" == "restore" ]; then 
    echo "1" >$backup_dir/test_file.csv
    echo "DROP TABLE IF EXISTS temp_backup_6hPh9hgW3qxu6cXCZzNA;
          CREATE TABLE temp_backup_6hPh9hgW3qxu6cXCZzNA ( f1 integer );
          COPY temp_backup_6hPh9hgW3qxu6cXCZzNA FROM '$backup_dir/test_file.csv';" | omnisql -p $password -q >/dev/null
    if [ $? != 0 ]; then
      echo "Error: Cannot read to temporary dir for the "$action". Exiting"
      cleanupBackupDir
      echo "drop table EXISTS temp_backup_6hPh9hgW3qxu6cXCZzNA;" omnisql -p $password -q $database_to_backup >/dev/null
      exit -1
    fi;
    echo "drop table EXISTS temp_backup_6hPh9hgW3qxu6cXCZzNA;" omnisql -p $password -q $database_to_backup >/dev/null
    rm $backup_dir/test_file.csv
  elif [ "$action" == "backup" ]; then 
    echo "COPY (SELECT 1) TO '$backup_dir/test_file.csv';" | omnisql -p $password -q $database_to_backup
    if [ $? != 0 ]; then
      echo "Error: Cannot write to temporary directory ("$backup_dir") for the "$action". Exiting"
      cleanupBackupDir
      exit -1
    fi;
  fi
}

function getDashboardAttr() {
  name_trimmed=$(echo $dashboard_name | cut -f 2 -d '|' | xargs)
  owner_trimmed=$(echo $dashboard_name | cut -f 3 -d '|' | xargs)
}

function checkBackupFile() {
  if [ ! -f "$backup_file" ]; then
    echo "Error: Cannot open backup file "$backup_file" for reading. Exiting";
    cleanupBackupDir
    exit -1
  fi;
  tar xf /mapd_storage/backup_kxn_db.tar -O $list_of_tables_filename >/dev/null
  if [ $? != 0 ]; then
    echo "Error: The backup file "$backup_file" is invalid. Exiting"
    cleanupBackupDir
    exit -1
  fi;
}

list_of_users=()
function addDBUser() {
    if [ "$(printf '%s\n' "${list_of_users[@]}" | grep -x $1)" == ""  ]; then
      list_of_users+=($1)
    fi;
}

function getPrivilegesTable() {
IFS='
'
  list_of_privileges_to_grant=()
  list_of_user_privs=$(echo "\object_privileges table "$1 | omnisql -p $password -q $database_to_backup)
  for l in $list_of_user_privs 
  do
    user_p=$(echo $l | cut -f 1 -d ' ')
    addDBUser $user_p
    list_of_privs=$(echo $l | cut -f 2 -d ':')
    if [ ! "$(echo "create, drop" | egrep "^create" )" == "" ]; then
      list_of_privs="all";
    fi;
    list_of_privileges_to_grant+=($(echo "GRANT "$list_of_privs" ON "$2" "$1" TO "$user_p";"))
  done;
}

function processTables() {
IFS='
'
  for table_name in $(cat $backup_dir/$list_of_tables_filename)
  do
    if [ "$action" = "backup" ]; then
      echo "Info: Adding table "$table_name" to dump file."
      getPrivilegesTable $table_name TABLE
      echo "dump table $table_name to '$backup_dir"/"$table_name.gz' with (compression='gzip');" | omnisql -p $password -q $database_to_backup >/dev/null
    elif [ "$action" = "restore" ]; then
      echo "Info: Restoring table "$table_name
      tar xf $backup_file -C $backup_dir --wildcards $table_name.*
      echo "restore table \""$table_name"\" from '"$backup_dir"/"$table_name".gz';" | omnisql -p $password -q $database_to_backup >/dev/null
    fi;
    if [ $? != 0 ]; then
      echo "Error: Cannot "$action" table "$table_name". Existing"
      cleanupBackupDir
      exit -1
    fi;
    if [[ "$action" == "restore" && "$import_privileges" == "yes" && -f $backup_dir"/"$table_name".sql" ]]; then
      echo "Info: Restoring privs for table "$table_name
      cat $backup_dir"/"$table_name".sql" | omnisql -p $password -q $database_to_backup >/dev/null
    fi;
    if [ "$action" == "backup" ]; then
      if [ "$list_of_privileges_to_grant" != "" ]; then
        printf '%s\n' "${list_of_privileges_to_grant[@]}" > $backup_dir/$table_name".sql"
        tar rf  $backup_file -C $backup_dir $table_name".sql" $table_name".gz"
      else
        tar rf  $backup_file -C $backup_dir $table_name".gz"
      fi;
      if [ $? != 0 ]; then
        echo "Error: Cannot backup table "$table_name". Existing"
        cleanupBackupDir
        exit -1
      fi;
    fi;
    rm $backup_dir/$table_name.*
  done;
}

function processViews() {
IFS='
' 
  if [ "$action" == "backup" ]; then
    echo "Info: Adding views definition and privilges to dump file."
  elif [[ "$action" == "restore" && "$import_privileges" == "yes" ]]; then
    echo "Info: Restoring views definitions and privileges."
  else
    echo "Info: Restoring views definitions"
  fi;
  for view_name in $(cat $backup_dir/$list_of_views_filename)
  do
    if [ "$action" == "backup" ]; then
      getPrivilegesTable $view_name VIEW
      echo "\d "$view_name | omnisql -p $password -q $database_to_backup >$backup_dir/$view_name".sql"
      if [ "$list_of_privileges_to_grant" != "" ]; then
        printf '%s\n' "${list_of_privileges_to_grant[@]}" >$backup_dir/$view_name"_p.sql"
        tar rf $backup_file -C $backup_dir $view_name"_p.sql"
      fi;
        tar rf $backup_file -C $backup_dir $view_name".sql"
    elif [ "$action" == "restore" ]; then
      echo "Info: Restoring view "$view_name
      tar xf $backup_file -C $backup_dir --wildcards $view_name"*.sql" >/dev/null
      cat $backup_dir/$view_name".sql" | omnisql -p $password -q $database_to_backup >/dev/null
    fi; 
    if [ $? != 0 ]; then
      echo "Error: Cannot "$action" view "$view_name". Existing"
      cleanupBackupDir
      exit -1
    fi;
    if [[ "$action" == "restore" && "$import_privileges" == "yes" && -f $backup_dir"/"$view_name"_p.sql" ]]; then
      echo "Info: Restoring privs for view "$table_name
      cat $backup_dir"/"$view_name"_p.sql" | omnisql -p $password -q $database_to_backup >/dev/null
    fi;
    rm $backup_dir/$view_name*.sql
  done;
}

function processDashboards() {
IFS='
'   
  for dashboard_name in $(cat $backup_dir/$list_of_dashboards_filename)
  do
    getDashboardAttr 
    if [ "$action" == "backup" ]; then
        addDBUser $owner_trimmed
        echo "Info: Adding dashboard "$name_trimmed" to backup file"
        echo "\export_dashboard \"$name_trimmed\" \"$backup_dir/$name_trimmed.bak\" " | omnisql -p $password -q $database_to_backup >/dev/null
        tar rf $backup_file -C $backup_dir $name_trimmed.bak >/dev/null
    elif [ "$action" == "restore" ]; then 
        echo "Info: Restoring dashboard "$name_trimmed"."
        tar xf $backup_file -C $backup_dir $name_trimmed.bak >/dev/null
        if [ $? == 0 ]; then
        echo "\import_dashboard \"$name_trimmed\" \"$backup_dir/$name_trimmed.bak\" " | omnisql -p $password  $database_to_backup >/dev/null
        fi;
    fi;
    rm "$backup_dir/$name_trimmed.bak"
  done;
}

export PATH=/opt/omnisci/bin/:/opt/heavyai/bin:$PATH
if [ "$(which omnisql)" == "" ]; then
  echo "Error: Cannot find omnisql. Add if to you PATH variable"
  echo "export PATH=/your_heavy_installation/bin:$PATH"
  exit -1
fi;

# start of the shell
for i in "$@"
do
  case $i in
    restore)
      action="restore"
      shift
      ;;
    dump)
      action="backup"
      shift
      ;;
    --user=*)
      username=${i#*=}
      shift
      ;;
    --password=*)
      password=${i#*=}
      shift
      ;;
    --database=*)
      database_to_backup=${i#*=}
      shift
      ;;
    --dumpfile=*)
      backup_file=${i#*=}
      shift
      ;;
    --dumpdir=*)
      backup_dir=${i#*=}/temp_backup_restore_heavy
      shift
      ;;
    --forcedb)
      force_dest_db_creation=yes;
      shift
      ;;
    --noprivs)
      import_privileges=no
      shift
      ;;
    --help)
      show_usage_and_exit 0
      shift
      ;;
     *)
       show_usage_and_exit 1
       ;;
  esac;
done;

 if [ "$action" == "" ]; then
   echo "Error: Choose if do a backup or a restore"
   show_usage_and_exit 1
 fi;

createAndCheckBackupDir
start_time=$(date +%s)

if [ "$action" = "backup" ]; then
  checkDatabaseExists
  echo "Info: Starting the backup of database "$database_to_backup"."
  echo "Info: Getting the list of the tables to backup."
  echo "show tables;" | omnisql -p $password -q $database_to_backup | grep -v "returned." >$backup_dir/$list_of_tables_filename
  if [ $(cat $backup_dir/$list_of_tables_filename | wc -l) = 0 ]; then
    echo "Error: Cannot find any table in the database "$database_to_backup" exiting";
    cleanupBackupDir
    exit -1
  fi;
  tar cf $backup_file -C $backup_dir $list_of_tables_filename >/dev/null
  if [ $? != 0 ]; then
    echo "Error: Cannot create the backup file ("$backup_file"). Exiting";
    cleanupBackupDir
    exit -1
  fi;
  
  echo "Info: Getting the list of the views to backup."
  echo "\v" | omnisql -p $password -q $database_to_backup | grep -v "returned." >$backup_dir/$list_of_views_filename
  if [ $(cat $backup_dir/$list_of_views_filename | wc -l ) -gt 0 ]; then
    tar rf $backup_file -C $backup_dir $list_of_views_filename
    processViews
  fi;
  echo "Info: Getting the list of the dashboards to backup."
  echo "\dash" | omnisql -p $password -q $database_to_backup | sort | egrep -v "Dashboard ID|display." >$backup_dir/$list_of_dashboards_filename
  if [ $(cat $backup_dir/$list_of_dashboards_filename | wc -l ) -gt 0 ]; then
    tar rf $backup_file -C $backup_dir $list_of_dashboards_filename
    processDashboards
  else
    echo "Info: No dashboards to backup."
  fi;
  rm $backup_dir/$list_of_dashboards_filename
  processTables
  printf '%s\n' "${list_of_users[@]}" >$backup_dir/$list_of_users_filename
  tar rf $backup_file -C $backup_dir $list_of_users_filename
  cleanupBackupDir
  end_time=$(date +%s)
  echo "Info: Backup of database "$database_to_backup" has been successful.
      Backup file "$backup_file".
      Elapsed time "$(( end_time - start_time ))" seconds
      File size "$(ls -sh $backup_file | cut -d ' ' -f 1)"."
elif [ "$action" == "restore" ]; then
  if [ "$force_dest_db_creation" != "yes" ]; then
    checkDatabaseExists
  else
    echo "CREATE DATABASE "$database_to_backup";" | omnisql -p $password -q 
    if [ $? != 0 ]; then
      echo "Error: Cannot create database "$database_to_backup". Exiting"
      cleanupBackupDir
      exit -1
    fi;
  fi;
  if [ "$import_privileges" == "yes" ]; then
    checkUsersExist
  fi;
  echo "Info: Starting the restore of database "$database_to_backup"."
  checkBackupFile
  echo "Info: Getting the list of the tables to restore."
  tar xf $backup_file -C $backup_dir $list_of_tables_filename
  processTables
  rm $backup_dir/$list_of_tables_filename
  tar xf $backup_file -C $backup_dir $list_of_dashboards_filename >/dev/null
  if [ $? == 0 ]; then
    processDashboards
  fi;
  tar xf $backup_file -C $backup_dir $list_of_views_filename >/dev/null
  if [ $? == 0 ]; then
    processViews
  fi;
  cleanupBackupDir
  end_time=$(date +%s)
  echo "Info: Restore of database "$database_to_backup" has been successful.
      Elapsed time "$(( end_time - start_time ))" seconds."
fi;

exit
