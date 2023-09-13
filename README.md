A simple script to dump and restore all tables, views, and dashboards of a HEAVY.AI database.

This utility does not utilize advanced or modern database features, relying solely on the legacy \ command of omnisql/heavysql, so it's going to work on almost very version.

The only database parameters requiring special attention are --allowed-export-paths in the source database and --allowed-import-paths in the destination database. These parameters must include the tempdir used by the utility during the dump and restore processes.

#### parameters

|  parameter name |parameter description|
| ------------ | ------------ |
|  dump, restore or duplicate | Use dump to back up your database and restore to restore into a new database. The experimental duplicate command duplicates all tables from the source --database into the --targetdatabase.  |
|--database=dbname| The database to dump/restore. Assumes the system is running on localhost using the default port. |
|  --dumpfile=dump_file_name | The name of the archive backup/restore file. Use --dumpdir=tempdir as the temporary directory. It must be accessible for read/write by the Heavy database, and set the allowed-import-paths and allowed-export-paths parameters in the instance.   |
|--forcedb | During restore, force the creation of a database if it does not exist. If the database already exists, return an error. |
|  --noprivs| During restore, don't import the object's privileges.|
| --user=username|Database username (defaults to 'admin').  |
|--password=pwd |database password [defaulta to HyperInteractive] |
|--targetdatabase| Used exclusively by the duplicate command, it specifies the name of the resulting duplicated database.|
|--uselz4| If available on the system, LZ4 will be used as the internal compressor. Backup time will significantly decrease, but the resulting dump archive will be around twice the size.|

##### examples:


Back up a database called "tpch_r" using the default user "admin" with the default password and gzip as the compressor,

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

If the --uselz4 parameter has been specified and LZ4 is available on the system, the drheavy.sh command will use LZ4 as the internal compressor. This will result in a significant decrease in backup time, but the size of the dump file will increase by approximately 70%.

```bash
Info: Backup of database tpch_r has been successful.
      Backup file /mapd_storage/dump_kxn.tar.
      Elapsed time 5 seconds
      File size 351M.
```

Restore the backup into a database called "tpch_r2" using the default user "admin" with the default password and forcing the database creation if it doesn't exist

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
Duplicate a database called tpch_r into a new one called tpch_dump using the lz4 compression for the maximum speed.

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
