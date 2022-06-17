# drdb_heavy

parameters:

backup|restore              use backup to backup your source database and restore to restore into
                            the new database
--database=database_name    name of the database to dump or restore
--dumpfile=dump_file        name of archive of backup/restore file
--dumpdir=tempdir           temp directory. Must be accessible in read/write by heavy database
                            set parameter allowed-import-paths and allowed-export-paths in the
                            instance
--forcedb                   on restore force the creation of a database if not exists.
                            if database already exists return an error
--noprivs                   don't import the privileges or objects
[--user=username]           database username [default to admin]
[--password=pwd]            database password [default to admin]

examples:

Backup a database called tpch_r using the deafult user admin with the default password

./backup_database.sh backup --database=tpch_r --dumpfile=/mapd_storage/

backup_kxn.tar.gz --dumpdir=/mapd_storage/  
Info: Starting the backup of database tpch_r.
Info: Getting the list of the tables to backup.
Info: Getting the list of the dashboards to backup.
Info: Adding dashboard test_backup_restore to backup file
Info: Adding dashboard dashboard (user test) to backup file
Info: Adding table temp_backup to backup file.
Info: Adding table lineitem to backup file.
Info: Adding table orders to backup file.
Info: Backup of database tpch_r has been successful.
      Backup file /mapd_storage/backup_kxn.tar.gz.
      Elapsed time 48 seconds
      File size 198M.

Restore into a database called tpch_r2 using the deafult user admin with the default password forcing the databse creation

./backup_database.sh restore --database=tpch_r2 --dumpfile=/mapd_storage/backup_kxn.tar.gz --dumpdir=/mapd_storage/  --forcedb 

Info: Starting the restore of database tpch_r2.
Info: Getting the list of the tables to restore.
Info: Restoring table temp_backup
Info: Restoring table lineitem
Info: Restoring table orders
Info: Restoring dashboard test_backup_restore.
Info: Restoring dashboard dashboard (user test).
Info: Restore of database tpch_r2 has been successful.
      Elapsed time 10 seconds.
