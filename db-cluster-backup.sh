#!/bin/bash

# variable setup
##########################################################
PGDATA="/var/data/pgdata15"
ARCHIVEDIR="/var/backups/archivedir"

BACKUP_DIR="/var/backups"
LOGICAL_BACKUP_DIR="$BACKUP_DIR/logical_backup"
BASE_BACKUP_DIR="$BACKUP_DIR/base_backup"

DATE=$(date +%Y_%m_%d_%H%M%S)
LOG_FILE="/var/backups/logs/backup_$DATE.log"

WAL_BACKUP_DIR="/var/backups/wal_backup"
LAST_WAL_BACKUP_FILE="/var/backups/last_wal_backup"

EMAIL="alan.hu@nzx.com"
WAL_RETENTION_DAYS=7
BACKUP_RETENTION_DAYS=1
LOG_RETENTION_DAYS=7

# feature flags
BASE_BACKUP_ENABLED=false
LOGICAL_BACKUP_ENABLED=false
DB_MAINTENANCE_ENABLED=true
HOUSEKEEPING_ENABLED=false
##########################################################

# check postgreSQL service running before backup
if pg_isready -q; then
    echo "PostgreSQL is running. Starting backup..." | tee -a $LOG_FILE


    # create backup directory

    mkdir -p $BASE_BACKUP_DIR/$DATE
    mkdir -p $LOGICAL_BACKUP_DIR/$DATE


    # base backup
    if [ "$BASE_BACKUP_ENABLED" = true ]; then
        echo "==========================================" | tee -a $LOG_FILE
        echo "Starting base backup..." | tee -a $LOG_FILE
        echo "==========================================" | tee -a $LOG_FILE       
        ###############################
        # backup the whole db cluster #
        ###############################
        pg_basebackup -D $BASE_BACKUP_DIR/$DATE -Ft -Xs -z -P -v

        if [ $? -eq 0 ]; then
            echo "Cluster backup completed successfully at $(date +%Y-%m-%d_%H:%M:%S)" | tee -a $LOG_FILE
        else
            echo "Cluster backup failed at $(date +%Y-%m-%d_%H:%M:%S)" | tee -a $LOG_FILE
            # echo "Cluster backup failed at $(date +%Y-%m-%d_%H:%M:%S)" | mail -s "PostgreSQL Backup Failed" $EMAIL
        fi
    fi



    # logical backup
    if [ "$LOGICAL_BACKUP_ENABLED" = true ]; then
        echo "==========================================" | tee -a $LOG_FILE
        echo "Starting logical backup..." | tee -a $LOG_FILE
        echo "==========================================" | tee -a $LOG_FILE
        # pg_dump backup each database
        for db in $(psql -At -c "SELECT datname FROM pg_database WHERE datistemplate = false;"); do
            pg_dump $db | gzip > $LOGICAL_BACKUP_DIR/$DATE/$db.sql.gz
            if [ $? -eq 0 ]; then
                echo "Database $db backup completed successfully at $(date +%Y-%m-%d_%H:%M:%S)" | tee -a $LOG_FILE
            else
                echo "Database $db backup failed at $(date +%Y-%m-%d_%H:%M:%S)" | tee -a $LOG_FILE
            fi
        done
    fi


    # database maintenance tasks
    if [ "$DB_MAINTENANCE_ENABLED" = true ]; then
        echo "==========================================" | tee -a $LOG_FILE
        echo "Starting database maintenance tasks..." | tee -a $LOG_FILE
        echo "==========================================" | tee -a $LOG_FILE
        ###############################
        # database maintenance tasks
        ###############################

        # reindex database
#        echo "Reindexing databases..." | tee -a $LOG_FILE
#        psql -c "REINDEX DATABASE postgres;" 2>&1 | tee -a $LOG_FILE

        # vacuum analyze
        echo "Vacuuming and analyzing databases..." | tee -a $LOG_FILE
        for db in $(psql -At -c "SELECT datname FROM pg_database WHERE datistemplate = false;"); do
            #psql -d $db -c "VACUUM (VERBOSE, ANALYZE);" 2>&1 | tee -a $LOG_FILE
            psql -d $db -c "VACUUM (ANALYZE);" 2>&1 | tee -a $LOG_FILE
        done

        echo "Database maintenance tasks completed." | tee -a $LOG_FILE
    fi


    # housekeeping tasks
    if [ "$HOUSEKEEPING_ENABLED" = true ]; then
        echo "==========================================" | tee -a $LOG_FILE
        echo "Starting housekeeping tasks..." | tee -a $LOG_FILE
        echo "==========================================" | tee -a $LOG_FILE
        ###############################
        # housekeeping tasks
        ###############################

        # delete old WAL files
        find $ARCHIVEDIR -type f -mtime +$WAL_RETENTION_DAYS -delete
        echo "Deleted WAL files older than $WAL_RETENTION_DAYS days" | tee -a $LOG_FILE

        # delete old base backups except the latest ones
        ls -dt $BASE_BACKUP_DIR/* | tail -n +$(($BACKUP_RETENTION_DAYS + 1)) | xargs rm -rf
        echo "Deleted old base backups except the latest ones" | tee -a $LOG_FILE

        # delete old logical backups except the latest ones
        ls -dt $LOGICAL_BACKUP_DIR/* | tail -n +$(($BACKUP_RETENTION_DAYS + 1)) | xargs rm -rf
        echo "Deleted old logical backups except the latest ones" | tee -a $LOG_FILE

        # delete old log files
        find /var/backups/logs -type f -mtime +$LOG_RETENTION_DAYS -delete
        echo "Deleted log files older than $LOG_RETENTION_DAYS days" | tee -a $LOG_FILE
    fi

else
    echo "PostgreSQL is not running at $(date +%Y-%m-%d_%H:%M:%S). Backup aborted." | tee -a $LOG_FILE
fi  

