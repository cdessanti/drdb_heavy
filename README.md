A simple script to dump and restore all tables, views and dashboards 
of an HEAVY.AI database.

The utility isn't using any advanced or modern features of the database, just the legacy \ command of omniscql/heavysql.

The only database parameters that need special attention are --allowed-export-paths in the source database and --allowed-import-paths in the destination database; they must contain the tempdir used in the utility during the dump and restore 

#### parameters

|  parameter name |parameter description|
| ------------ | ------------ |
|  dump, restore or duplicate | use dump to backup your database and restore to restore into the new database. use the --database switch to specify the database to dump/restore. The experimental duplicate command will duplicate all the tables in source --database into the --targetdatabase  |
|--database=dbname| the database to dump/restore. it's assume that's the system in running on localhost using the default port |
|  --dumpfile=dump_file name | name of the archive of backup/restore file --dumpdir=tempdir temp directory. Must be accessible in read/write by heavy database set parameter allowed-import-paths and allowed-export-paths in the instance   |
|--forcedb | during restore force the creation of a database if not exists. if the database already exists return an error |
|  --noprivs| during restore don't import the privileges on objects. everything|
| --user=username|database username [defaults to admin]  |
|--password=pwd |database password [default to HyperInteractive] |
|--targetdatabase| use by the duplicate command only. It's the name of the duplicated database|
|--uselz4| if avaiable in the system the the lz4 will be used as internal compressor. the time of backup will decrease drammatically but the resulting dump archive will be around twice the size|

##### examples:

Backup a database called tpch_r using the deafult user admin with the default password, using the gzip as compressor

```bash
./drdbheavy.sh dump --database=tpch_r \
--dumpfile=/mapd_storage/dump_kxn.tar \
--dumpdir=/mapd_storage/
```

output

```bash
Info: Starting the backup of database tpch_r.
Info: Getting the list of the tables to backup.
Info: Getting the list of the views to backup.
Info: Adding views definition and privilges to dump file.
Info: Getting the list of the dashboards to backup.
Info: Adding dashboard test_backup_restore to backup file
Info: Adding dashboard dashboard (user test) to backup file
Info: Adding table temp_backup to dump file.
Info: Adding table lineitem to dump file.
Info: Adding table orders to dump file.
Info: Backup of database tpch_r has been successful.
      Backup file /mapd_storage/dump_kxn.tar.
      Elapsed time 49 seconds
      File size 198M.
```

if the lz4 is avaiable, the drheavy.sh command will use as internal compressor. the time of the backup will decrease dramatically but the 

Info: Backup of database tpch_r has been successful.
      Backup file /mapd_storage/dump_kxn.tar.
      Elapsed time 5 seconds
      File size 351M.


Restore into a database called tpch_r2 using the deafult user admin with the default password forcing the databse creation.

```bash
./drdbheavy.sh restore --database=tpch_r2 \
--dumpfile=/mapd_storage/dump_kxn.tar \
--dumpdir=/mapd_storage/ --forcedb
```

output

```bash
Info: Starting the restore of database tpch_r2.
Info: Getting the list of the tables to restore.
Info: Restoring table temp_backup
Info: Restoring privs for table temp_backup
Info: Restoring table lineitem
Info: Restoring privs for table lineitem
Info: Restoring table orders
Info: Restoring dashboard test_backup_restore.
Info: Restoring dashboard dashboard (user test).
Info: Restoring views definitions and privileges.
Info: Restoring view v_test
Info: Restoring privs for view orders
Info: Restore of database tpch_r2 has been successful.
      Elapsed time 11 seconds.
```
Duplicate a database called into using the lz4 compression for the maximum speed up

```bash
./drdbheavy.sh duplicate --database=tpch_r --targetdatabase=tpch_dump \
 --dumpdir=/mapd_storage/ --forcedb --uselz4
```

output 

```bash
Info: Using lz4 as internal compressor.
cat: list_of_users.txt: No such file or directory
Info: Copying table temp_backup
Info: Copied table temp_backup
Info: Copying table lineitem
Info: Copied table lineitem
Info: Copying table orders
Info: Copied table orders
Info: The duplication of database tpch_r has been successful.
      Elapsed time 7 seconds.
```