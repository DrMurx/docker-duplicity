#! /bin/bash


KEYS_VOLUME="/keys"
ARCHIVE_VOLUME="/archive"
DATA_VOLUME="/data"
BACKUP_HOST="${BACKUP_HOST:-backupserver}"
BACKUP_BASE_URL="${BACKUP_BASE_URL:-sftp://${BACKUP_HOST}}"


function error() {
  echo "Error: $@"
  exit 1
}


function headline() {
  printf '=%.0s' $(seq 1 ${#1})
  echo
  echo "${1}"
  printf '=%.0s' $(seq 1 ${#1})
  echo
  echo
}


function initKeys() {
  headline "Installing SSH keys"
  if [ ! -e /root/.ssh/config ]; then
    [ -e ${KEYS_VOLUME}/backup-ssh ] || error "SSH keys not in /keys volume!"
    mkdir -p /root/.ssh
    cp -a ${KEYS_VOLUME}/backup-ssh/* /root/.ssh/
    ssh-keygen -p -N "" -f /root/.ssh/id_rsa
    echo "  done"
  else
    echo "  already done"
  fi

  headline "Installing GPG keys"
  if [ ! -e /root/.gnupg/pubring.gpg ]; then
    [ -e ${KEYS_VOLUME}/backup-gnupg ] || error "GPG keys not in ${KEYS_VOLUME} volume!"
    mkdir -p /root/.gnupg
    cp -a ${KEYS_VOLUME}/backup-gnupg/* /root/.gnupg/
    echo "  done"
  else
    echo "  already done"
  fi
}


function dumpMysql() {
  DUMP_FILE=${DATA_VOLUME}/database/mysql_${MYSQL_HOST}_${MYSQL_DATABASE}.sql
  echo "Dumping Mysql/MariaDB to ${DUMP_FILE}"
  mkdir -p ${DATA_VOLUME}/database
  mysqldump -h ${MYSQL_HOST} \
            -P ${MYSQL_PORT:-3306} \
            -u ${MYSQL_USER:-root} \
            -p${MYSQL_PASSWORD} \
            ${MYSQL_DATABASE} \
            > ${DUMP_FILE}.tmp || exit 1
  if [ ! -e ${DUMP_FILE} ] || ! diff ${DUMP_FILE}.tmp ${DUMP_FILE} >/dev/null; then
    mv -f ${DUMP_FILE}.tmp ${DUMP_FILE}
    echo "  done"
  else
    rm ${DUMP_FILE}.tmp
    echo "  No changes to previous dump, skipping..."
  fi
}


function dumpPostgresql() {
  DUMP_FILE=${DATA_VOLUME}/database/pg_${POSTGRES_HOST}_${POSTGRES_DATABASE}.sql
  echo "Dumping Postgres to ${DUMP_FILE}"
  mkdir -p ${DATA_VOLUME}/database
  PGPASSWORD=${POSTGRES_PASSWORD} \
    pg_dump -h ${POSTGRES_HOST} \
            -p ${POSTGRES_PORT:-5432} \
            -U ${POSTGRES_USER:-postgres} \
            -f ${DUMP_FILE}.tmp \
            ${POSTGRES_DATABASE} || exit 1
  if [ ! -e ${DUMP_FILE} ] || ! diff ${DUMP_FILE}.tmp ${DUMP_FILE} >/dev/null; then
    mv -f ${DUMP_FILE}.tmp ${DUMP_FILE}
    echo "  done"
  else
    rm ${DUMP_FILE}.tmp
    echo "  No changes to previous dump, skipping..."
  fi
}


## Assemble final BACKUP_BASE_URL
[[ $(hostname -s) =~ ^[0-9a-f]{12}$ ]] && error "Please specify the --hostname parameter on docker run!"
BACKUP_BASE_URL="${BACKUP_BASE_URL}/$(hostname -f)"

## Assure permissions
chown -R root:root /root/.ssh /root/.gnupg
find /root/.ssh -type d -exec chmod 700 {} \;
find /root/.ssh -type f -exec chmod 600 {} \;
find /root/.gnupg -type d -exec chmod 700 {} \;
find /root/.gnupg -type f -exec chmod 600 {} \;

## Docker breaks tty handling so we need to start gpg-agent manually with --allow-loopback-pinentry
pkill gpg-agent
echo "allow-loopback-pinentry" > /root/.gnupg/gpg-agent.conf
gpg-agent --homedir /root/.gnupg --daemon --allow-loopback-pinentry --log-file=/dev/null


case "${1}" in
  backup)
    [ -n "${BACKUP_NAME}" ] || error "Please pass the BACKUP_NAME variable"
    [ -n "${PGP_ENCRYPT_KEY}" ] || error "Please pass the PGP_ENCRYPT_KEY variable"
    [[ -e /root/.ssh/config && -e /root/.gnupg/pubring.gpg ]] || error "Keys are not installed. Provide them via volume, or run 'init' first!"

    headline "Backup ${BACKUP_NAME}"

    mkdir -p "${DATA_VOLUME}"

    [[ -n "${MYSQL_HOST}"    && -n "${MYSQL_DATABASE}" ]]    && dumpMysql
    [[ -n "${POSTGRES_HOST}" && -n "${POSTGRES_DATABASE}" ]] && dumpPostgresql
    [[ -n "${BACKUP_BEFORE_COMMAND}" ]] && eval "${BACKUP_BEFORE_COMMAND}"

    BACKUP_URL=${BACKUP_BASE_URL}/${BACKUP_NAME}

    echo "Start duplicity backup to ${BACKUP_URL}"
    duplicity --archive-dir="${ARCHIVE_VOLUME}" \
              --name="${BACKUP_NAME}" \
              --gpg-options="--pinentry-mode=loopback" \
              --encrypt-key="${PGP_ENCRYPT_KEY}" \
              --full-if-older-than=1M \
              --volsize=512 \
              --timeout=1200 \
              "${DATA_VOLUME}" \
              "${BACKUP_URL}" \
      | sed -e 's/^/  /g'

    echo "Expire old backups on ${BACKUP_URL}"
    duplicity --archive-dir="${ARCHIVE_VOLUME}" \
              --name="${BACKUP_NAME}" \
              remove-all-inc-of-but-n-full 3 \
              "${BACKUP_URL}" \
      | sed -e 's/^/  /g'
    duplicity --archive-dir="${ARCHIVE_VOLUME}" \
              --name="${BACKUP_NAME}" \
              remove-all-but-n-full 6 \
              "${BACKUP_URL}" \
      | sed -e 's/^/  /g'
    ;;

  restore)
    [ -n "${BACKUP_NAME}" ] || error "Please pass the BACKUP_NAME variable"

    headline "Restore ${BACKUP_NAME}"

    mkdir -p "${DATA_VOLUME}"

    if [ $(find "${DATA_VOLUME}" | wc -l) -ne 1]; then
      error "Restore target directory is not empty!"
    fi

    BACKUP_URL=${BACKUP_BASE_URL}/${BACKUP_NAME}

    echo "Start duplicity restore from ${BACKUP_URL}"
    duplicity --archive-dir="${ARCHIVE_VOLUME}" \
              --name="${BACKUP_NAME}" \
              --gpg-options="--pinentry-mode=loopback" \
              restore \
              "${BACKUP_URL}" \
              "${DATA_VOLUME}" \
      | sed -e 's/^/  /g'
    ;;

  status)
    BACKUP_NAME="${2:-${BACKUP_NAME}}"
    [ -n "${BACKUP_NAME}" ] || error "Please pass the BACKUP_NAME variable"

    headline "Collection status of ${BACKUP_NAME}"

    BACKUP_URL=${BACKUP_BASE_URL}/${BACKUP_NAME}

    duplicity --archive-dir="${ARCHIVE_VOLUME}" \
              --name="${BACKUP_NAME}" \
              collection-status \
              "${BACKUP_URL}" \
      | sed -e 's/^/  /g'
    ;;

  full-status)
    headline "Collection status"
    for BACKUP_NAME in $(cd /archive; ls -1); do
      BACKUP_URL=${BACKUP_BASE_URL}/${BACKUP_NAME}
      echo "${BACKUP_NAME}"
      echo
      duplicity --archive-dir="${ARCHIVE_VOLUME}" \
                --name="${BACKUP_NAME}" \
                collection-status \
                "${BACKUP_URL}" \
        | sed -e 's/^/  /g'
      echo
      echo
    done
    ;;

  df)
    headline "Backup space information"
    echo "df -h" | sftp "${BACKUP_HOST}"
    ;;

  init)
    initKeys
    ;;

  shell)
    headline "Welcome to Duplicity Backup Shell"
    [[ -e /root/.ssh/config && -e /root/.gnupg/pubring.gpg ]] || echo "Don't forget to run 'backup init' to setup the keys."
    echo
    /bin/bash
    ;;

  help|-h|--help)
    echo "See README.md for usage."
    ;;

  '')
    error "No command given!"
    ;;

  *)
    error "Unknown command given: ${1}"
    ;;
esac
