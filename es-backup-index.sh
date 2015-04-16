#!/bin/bash

# by Serge D  2015 sergeserg@yandex.ru

# This is a wrapper script for daily run
# i.e. you can run it by cron as follows
## m h  dom mon dow   command
#  11 4 * * * /opt/es/es-backup-index.sh >> /var/log/elasticsearch/esindexbackup.log 

# Assuming you have the scripts inside '/opt/es/' folder. Or adjust the path to your taste.
#
# Set your system realities here
S3URL="s3://elasticsearch-backups"
ESDATA="/mnt/disk2/es/data/elasticsearch/nodes/0/indices/"
DAYS=7

# Read through all the available ES indices and generate a list of unique index names
# then proceed on all the indices
for i in `ls -1 $ESDATA | sed -r -e 's/-+[0-9]{4}\.[0-9]{2}\.[0-9]{2}$//' | uniq` ; do

   echo -n " *** Daily index backup for index name '$i' begin:  "
   date
   /opt/es/elasticsearch-backup-index.sh -b $S3URL -i $ESDATA -g $i

   echo -n " *** Close indices for index name '$i' which are  > $DAYS days old :  " 
   date
   /opt/es/elasticsearch-close-old-indices.sh -i $DAYS -g $i

   echo -n " *** Delete indices for index name '$i' which are > $DAYS days old :  "
   date
   /opt/es/elasticsearch-remove-old-indices.sh -i $DAYS -g $i
   echo " ==== Done for index name '$i' ==== "
   echo " "
done

echo -n " ******* FINISHED :  "
date
