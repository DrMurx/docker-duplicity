# Duplicity Backup for Container Environments

This is an all-purpose backup tool for your container environment.


## Usage

### Variables

* `BACKUP_HOST`: Host to backup to (default: backupserver)
* `BACKUP_BASE_URL`: Duplicity compatible URL to store the backup to (default: `sftp://$BACKUP_HOST`)
* `BACKUP_NAME`: Duplicity name for the backup
* `PGP_ENCRYPT_KEY`: Username, email or GPG Key ID for backup encryption.


### Commands

* `backup`: Backup
* `restore`: Restore
* `status`: Show the status of `BACKUP_NAME`.
* `full-status`: Show the status of all dupliticy backups
* `df`: Show the free disk space on the SFTP host
* `init`: Initialize the key, see [below](#key-initialization)
* `shell`: Spawn a bash in the container


### Add volumes to backup

The script backups the container directory `/data`. To backup specific volumes, just mount them below `/data` using `docker run --volume`.

Note: The directory `/data/database` is reserved for database dumps.


### Add database dumps to backup

To backup a mysql instance, provide these variables:

* `MYSQL_HOST`
* `MYSQL_PORT` (default: 3306)
* `MYSQL_USER` (default: root)
* `MYSQL_PASSWORD`
* `MYSQL_DATABASE`

To backup a postgres instance, provide these variables:

* `POSTGRES_HOST`
* `POSTGRES_PORT` (default: 5432)
* `POSTGRES_USER` (default: postgres)
* `POSTGRES_PASSWORD`
* `POSTGRES_DATABASE`

Databases will be dumped to `/data/database`.


### Keys

Mount a volume at `/root/.gnupg` with the PGP keyring to decrypt and encrypt backups. If the key is protected with a passphrase, it's only required for the `restore` command. It might be required for the commands `status` and`full-status` if you didn't provide an `/archive` mountpoint.

Mount a volume at `/root/.ssh` with a proper SSH `config`, `known_hosts` and `id_rsa` to log into your backup server. If the key is protected with a passphrase, you have to enter it for the `backup` and `restore` command.


#### Key initialization

The `init` command provides a way to store keep the keys in a external repository. Mount a volume at `/keys`, containing two directories:

- `/keys/backup-ssh` contains the SSH keys
- `/keys/backup-gnupg` contains the GPG keyring

During `init`, any passphrase will be removed from the SSH keys, and all files will be put in proper place at `/root/.gnupg` and `/root/.ssh` so you don't have to provide those directories as host mount.


### Local duplicity metadata archive

In case you want to keep a local copy of the duplicity metadata archive, mount a volume at `/archive`. If you don't provide this mount, dupliticy has to fetch and decrypt the metadata before every backup, which might require the private GPG key's passphrase.
