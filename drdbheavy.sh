#!/bin/bash

#defaults and fixed variables
username=admin
password=HyperInteractive
import_privileges=yes
list_of_tables_filename=list_of_tables.txt
list_of_dashboards_filename=list_of_dashboards.txt
list_of_users_filename=list_of_users.txt
list_of_views_filename=list_of_views.txt
compressor="gzip"
#list of severity
INFO_S="Info"
WARNING_S="Warning"
ERROR_S="Error"
SQLCLIENT="omnisql"
root_database=""

function show_usage_and_exit()  {
  echo "Usage: drdbheavy.sh dump|restore|duplicate --database=database_name --dumpfile=dump_file --dumpdir=tempdir [--forcedb] [--noprivs] [--user=username] [--password=pwd] [--targetdatabase=dbname] [--uselz4]"
  echo "dump|restore|duplicate:     Create a dump, restore, or duplicate the specified database using the --database switch"
  echo "--database=dbname:          The name of the database to be dumped, restored, or duplicated"
  echo "--dumpfile=filename:        The file containg the backup"
  echo "--tempdir=dirname:          A temporary directory used by the utility to read/write files, accessible by the source/target database"
  echo "--forcedb:                  Force the creation of a target database in case of restore/duplicate"
  echo "--noprivs:                  Do not grant any privileges in the target database"
  echo "--user=username:            Username for the source/target database"
  echo "--password=pwd:             Password of the user"
  echo "--targetdatabase=dbname:    Name of the duplicated database"
  echo "--uselz4:                   Use the lz4 compression instead of gzip"
  exit $1
}

function findDefaultDatabase() {
  for default_database in heavyai omnisci mapd
  do
    echo "select 1;" | $SQLCLIENT -u $username -p $password -q $default_database >/dev/null
    if [ "$?" == "0" ]; then
      root_database=$default_database
      log $INFO_S "Using "$root_database" as root database"
      break;
    fi;
  done;
  if [ "$root_database" == "" ]; then
    log $ERROR_S "Cannot find the root database. Exiting"
    exit 1
  fi;
}

function checkDatabaseExists() {
  database_exists=$(echo "show databases;" | $SQLCLIENT -u $username -p $password $1 -q | egrep "^$1\|" | cut -f 1 -d '|')
  if [ "$database_exists" == "" ]; then
    log $ERROR_S "Cannot connect to the database: "$database_to_backup".\nCheck that your username and password are correct and that the database exist";
    cleanupBackupDir
    exit -1
  fi;
}

function checkUsersExist() {
  tar xf "$backup_file" --force-local -C  $backup_dir $list_of_users_filename
  if [ -f $list_of_users_filename ]; then
    for i in $(cat $list_of_users_filename)
    do
      if [ "$i" != "admin" ]; then 
        echo "show user details "$i | $SQLCLIENT -p HyperInteractive -q $root_database 2>/dev/null >/dev/null
        if [ $? == 0 ]; then
          cleanupBackupDir
          log $ERROR_S "User "$i" doesn't exist in the target database. Exiting"
          exit -1
        fi;
      fi;
    done;
  fi;
}

function cleanupBackupDir() {
  rm -Rf $backup_dir
}

function createAndCheckBackupDir() {
  mkdir $backup_dir
  if [ $? != 0 ]; then
    log $ERROR_S "Cannot create the temporary directory ("$backup_dir"). Exiting"
    exit -1
  fi;
  if [ "$action" == "restore" ]; then 
    echo "1" >$backup_dir/test_file.csv
    echo "DROP TABLE IF EXISTS temp_backup_6hPh9hgW3qxu6cXCZzNA;
          CREATE TABLE temp_backup_6hPh9hgW3qxu6cXCZzNA ( f1 integer );
          COPY temp_backup_6hPh9hgW3qxu6cXCZzNA FROM '$backup_dir/test_file.csv';" | $SQLCLIENT -p $password -q $root_database >/dev/null
    if [ $? != 0 ]; then
      log $ERROR_S "Cannot read from the temporary directory ("$temp_dir"). Exiting"
      cleanupBackupDir
      echo "drop table EXISTS temp_backup_6hPh9hgW3qxu6cXCZzNA;" $SQLCLIENT -p $password -q $database_to_backup >/dev/null
      exit -1
    fi;
    echo "drop table EXISTS temp_backup_6hPh9hgW3qxu6cXCZzNA;" $SQLCLIENT -p $password -q $database_to_backup >/dev/null
    rm $backup_dir/test_file.csv
  elif [ "$action" == "backup" ]; then 
    echo "COPY (SELECT 1) TO '$backup_dir/test_file.csv';" | $SQLCLIENT -p $password -q $database_to_backup
    if [ $? != 0 ]; then
      log $ERROR_S "The database cannot write to the backup directory ("$temp_dir").\nPlease add the directory in the --allowed-import-paths and --allowed-export-paths and restart the database"
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
    log $ERROR_S "Cannot open backup file "$backup_file" for reading. Exiting";
    cleanupBackupDir
    exit -1
  fi;
  tar xf "$backup_file" --force-local -O $list_of_tables_filename >/dev/null
  if [ $? != 0 ]; then
    log $ERROR_S "The backup file "$backup_file" is invalid. Exiting"
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
  list_of_user_privs=$(echo "\object_privileges table "$1 | $SQLCLIENT -p $password -q $database_to_backup)
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

function processSingleTable()
{
  if [ "$action" == "duplicate" ]; then
    log $INFO_S "Copying table "$table_name
    getPrivilegesTable $table_name TABLE
    echo "dump table $table_name to '$backup_dir"/"$table_name.dmp' with (compression='$compressor');" | $SQLCLIENT -p $password -q $database_to_backup >/dev/null
    echo "restore table $table_name from '$backup_dir"/"$table_name.dmp' with (compression='$compressor');" | $SQLCLIENT -p $password -q $database_to_restore >/dev/null
    if [ $? != 0 ]; then
      log $ERROR_S "Cannot "$action" table "$table_name". Exiting"
      cleanupBackupDir
      exit -1
    fi;
    rm $backup_dir"/"$table_name.dmp;
    log $INFO_S "Copied table "$table_name
  fi;
}
function processTables() {
IFS='
'
  for table_name in $(cat $backup_dir/$list_of_tables_filename)
  do
    if [ "$action" = "backup" ]; then
      log $INFO_S "Adding table "$table_name" to dump file"
      getPrivilegesTable $table_name TABLE
      echo "dump table $table_name to '$backup_dir"/"$table_name.dmp' with (compression='$compressor');" | $SQLCLIENT -p $password -q $database_to_backup >/dev/null
    elif [ "$action" = "restore" ]; then
      log $INFO_S "Restoring table "$table_name
      tar xf "$backup_file" --force-local -C  $backup_dir --wildcards $table_name.*
      echo "restore table \""$table_name"\" from '"$backup_dir"/"$table_name".dmp' with (compression='$compressor');" | $SQLCLIENT -p $password -q $database_to_backup >/dev/null
    fi;
    if [ $? != 0 ]; then
      log $ERROR_S "Cannot "$action" table "$table_name". Exiting"
      cleanupBackupDir
      exit -1
    fi;
    if [[ "$action" == "restore" && "$import_privileges" == "yes" && -f $backup_dir"/"$table_name".sql" ]]; then
      log $INFO_S "Restoring privileges for table "$table_name
      cat $backup_dir"/"$table_name".sql" | $SQLCLIENT -p $password -q $database_to_backup >/dev/null
    fi;
    if [ "$action" == "backup" ]; then
      if [ "$list_of_privileges_to_grant" != "" ]; then
        printf '%s\n' "${list_of_privileges_to_grant[@]}" > $backup_dir/$table_name".sql"
        tar rf "$backup_file" --force-local -C  $backup_dir $table_name".sql" $table_name".dmp"
      else
        tar rf "$backup_file" --force-local -C  $backup_dir $table_name".dmp"
      fi;
      if [ $? != 0 ]; then
        log $ERROR_S "Cannot backup table "$table_name". Exiting"
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
    log $INFO_S "Adding views definition and privileges to dump file."
  elif [[ "$action" == "restore" && "$import_privileges" == "yes" ]]; then
    log $INFO_S "Restoring views definitions and privileges."
  else
    log $INFO_S "Restoring views definitions"
  fi;
  for view_name in $(cat $backup_dir/$list_of_views_filename)
  do
    if [ "$action" == "backup" ]; then
      getPrivilegesTable $view_name VIEW
      echo "\d "$view_name | $SQLCLIENT -p $password -q $database_to_backup >$backup_dir/$view_name".sql"
      if [ "$list_of_privileges_to_grant" != "" ]; then
        printf '%s\n' "${list_of_privileges_to_grant[@]}" >$backup_dir/$view_name"_p.sql"
        tar rf "$backup_file" --force-local -C  $backup_dir $view_name"_p.sql"
      fi;
        tar rf "$backup_file" --force-local -C  $backup_dir $view_name".sql"
    elif [ "$action" == "restore" ]; then
      echo "Info: Restoring view "$view_name
      tar xf "$backup_file" --force-local -C  $backup_dir --wildcards $view_name"*.sql" >/dev/null
      cat $backup_dir/$view_name".sql" | $SQLCLIENT -p $password -q $database_to_backup >/dev/null
    fi; 
    if [ $? != 0 ]; then
      log $ERROR_S "Cannot "$action" view "$view_name". Exiting"
      cleanupBackupDir
      exit -1
    fi;
    if [[ "$action" == "restore" && "$import_privileges" == "yes" && -f $backup_dir"/"$view_name"_p.sql" ]]; then
      log $INFO_S "Restoring privileges for view "$table_name
      cat $backup_dir"/"$view_name"_p.sql" | $SQLCLIENT -p $password -q $database_to_backup >/dev/null
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
        log $INFO_S "Adding dashboard "$name_trimmed" to backup file"
        echo "\export_dashboard \"$name_trimmed\" \"$backup_dir/$name_trimmed.bak\" " | $SQLCLIENT -p $password -q $database_to_backup >/dev/null
        tar rf "$backup_file" --force-local -C  $backup_dir $name_trimmed.bak >/dev/null
    elif [ "$action" == "restore" ]; then 
        log $INFO_S "Restoring dashboard "$name_trimmed"."
        tar xf "$backup_file" --force-local -C  $backup_dir $name_trimmed.bak >/dev/null
        if [ $? == 0 ]; then
        echo "\import_dashboard \"$name_trimmed\" \"$backup_dir/$name_trimmed.bak\" " | $SQLCLIENT -p $password  $database_to_backup >/dev/null
        fi;
    fi;
    rm "$backup_dir/$name_trimmed.bak"
  done;
}

function checkCommandAndUtilities() {
# Search for command and utilities needed
  export PATH=/opt/omnisci/bin/:/opt/heavyai/bin:$PATH
  if [ "$(which omnisql)" == "" ]; then
    if [ "$(which heavysql)" == "" ]; then
      log $ERROR_S "Cannot find omnisql or heavysql command.\nAdd the installation directory to the PATH variable with the following command\nexport PATH=/your_heavy_installation/bin:\$PATH\nExiting"
      exit -1
    fi;
    SQLCLIENT="heavysql"
  fi;
  SQLCLIENT="omnisql"
}

function setCompressor() {
  if [ "$(which lz4)" != "" ]; then
    log $INFO_S "Using lz4 as internal compressor"
    compressor="lz4"
  else
    log WARN_S "Cannot find lz4, using gzip as internal compressor"
    compressor="gzip"
  fi;
}

function log() {
  severity=$1
  message=$2
  echo -e $severity": "$message"."
}

# Start of the shell
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
    duplicate)
      action="duplicate"
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
    --targetdatabase=*)
      database_to_restore=${i#*=}
      shift
      ;;
    --dumpfile=*)
      backup_file=${i#*=}
      shift
      ;;
    --tempdir=*)
      temp_dir=${i#*=}
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
    --uselz4)
      setCompressor
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


case $action in
  backup|restore|duplicate)
  ;;
  *)
   log $ERROR_S_S "Please select DUMP, RESTORE or DUPLICATE as action."
   show_usage_and_exit 1
esac;

checkCommandAndUtilities
findDefaultDatabase
createAndCheckBackupDir
start_time=$(date +%s)

if [ "$action" = "backup" ]; then
  checkDatabaseExists $database_to_backup
  log $INFO_S "Starting the backup of database "$database_to_backup"."
  log $INFO_S "Getting the list of the tables to backup"
  echo "show tables;" | $SQLCLIENT -p $password -q $database_to_backup | grep -v "returned." >$backup_dir/$list_of_tables_filename
  if [ $(cat $backup_dir/$list_of_tables_filename | wc -l) = 0 ]; then
    log $ERROR_S "Cannot find any table in the database "$database_to_backup" Exiting";
    cleanupBackupDir
    exit -1
  fi;
  tar cf "$backup_file" --force-local -C $backup_dir $list_of_tables_filename >/dev/null
  if [ $? != 0 ]; then
    log $ERROR_S "Cannot create the backup file ("$backup_file"). Exiting";
    cleanupBackupDir
    exit -1
  fi;
  
  log $INFO_S "Getting the list of the views to backup"
  echo "\v" | $SQLCLIENT -p $password -q $database_to_backup | grep -v "returned." >$backup_dir/$list_of_views_filename
  if [ $(cat $backup_dir/$list_of_views_filename | wc -l ) -gt 0 ]; then
    tar rf "$backup_file" --force-local -C  $backup_dir $list_of_views_filename
    processViews
  fi;
  log $INFO_S "Getting the list of the dashboards to backup"
  echo "\dash" | $SQLCLIENT -p $password -q $database_to_backup | sort | egrep -v "Dashboard ID|display." >$backup_dir/$list_of_dashboards_filename
  if [ $(cat $backup_dir/$list_of_dashboards_filename | wc -l ) -gt 0 ]; then
    tar rf "$backup_file" --force-local -C  $backup_dir $list_of_dashboards_filename
    processDashboards
  else
    log $INFO_S "No dashboards to backup"
  fi;
  rm $backup_dir/$list_of_dashboards_filename
  processTables
  printf '%s\n' "${list_of_users[@]}" >$backup_dir/$list_of_users_filename
  tar rf "$backup_file" --force-local -C  $backup_dir $list_of_users_filename
  cleanupBackupDir
  end_time=$(date +%s)
  log $INFO_S "Backup of database "$database_to_backup" has been successful.\n      Backup file "$backup_file" with File Size "$(ls -sh "$backup_file" | cut -d ' ' -f 1)
  log $INFO_S "Elapsed time "$(( end_time - start_time ))" seconds"
elif [ "$action" == "restore" ]; then
  if [ "$force_dest_db_creation" != "yes" ]; then
    checkDatabaseExists $database_to_backup
  else
    echo "CREATE DATABASE "$database_to_backup";" | $SQLCLIENT -p $password -q 
    if [ $? != 0 ]; then
      log $ERROR_S "Cannot create database "$database_to_backup". Exiting"
      cleanupBackupDir
      exit -1
    fi;
  fi;
  if [ "$import_privileges" == "yes" ]; then
    checkUsersExist
  fi;
  log $INFO_S "Starting the restore of database "$database_to_backup"."
  checkBackupFile
  log $INFO_S "Getting the list of the tables to restore."
  tar xf "$backup_file" --force-local -C  $backup_dir $list_of_tables_filename
  processTables
  rm $backup_dir/$list_of_tables_filename
  tar xf "$backup_file" --force-local -C  $backup_dir $list_of_dashboards_filename 2>/dev/null 1>/dev/null
  if [ $? == 0 ]; then
    processDashboards
  fi;
  tar xf "$backup_file" --force-local -C  $backup_dir $list_of_views_filename 2>/dev/null 1>/dev/null
  if [ $? == 0 ]; then
    processViews
  fi;
  cleanupBackupDir
  end_time=$(date +%s)
  log $INFO_S "Restore of database "$database_to_backup" has been successful."
  log $INFO_S "Elapsed time "$(( end_time - start_time ))" seconds."
elif [ "$action" == "duplicate" ]; then
  if [ "$force_dest_db_creation" != "yes" ]; then
    checkDatabaseExists $database_to_restore
  else
    echo "CREATE DATABASE "$database_to_restore";" | $SQLCLIENT -p $password -q $root_database
    if [ $? != 0 ]; then
      log $ERROR_S "Cannot create database "$database_to_restore". Exiting"
      cleanupBackupDir
      exit -1
    fi;
  fi;
  #if [ "$import_privileges" == "yes" ]; then
  #  checkUsersExist
  #fi;

  echo "show tables;" | $SQLCLIENT -p $password -q $database_to_backup | grep -v "returned." >$backup_dir/$list_of_tables_filename
  for table_name in $(cat $backup_dir/$list_of_tables_filename)
  do
    processSingleTable
  done;
  end_time=$(date +%s)
  log $INFO_S "The duplication of database "$database_to_backup" has been successful"
  log $INFO_S "Total Elapsed time "$(( end_time - start_time ))" seconds"
  cleanupBackupDir
  exit 0
fi;
exit 0
