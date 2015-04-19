## Elasticsearch Logstash Index Management

Please note that [Elasticsearch](http://github.com/elasticsearch) provides the
python based [Curator](http://github.com/elasticsearch/curator) which manages
closing/deleting and maintenance with lots of tuning capabilities. It is worth
investigating Curator as an elasticsearch-maintained solution for your cluster's
time-based index maintenance needs.

If you are using Curator with Elasticsearch >= 1.0.0 (and
[Hubot](https://hubot.github.com/)) and you want a way to restore old indices,
try [hubot-elk-restore](https://github.com/imperialwicket/hubot-elk-restore).

If you prefer to roll your own, or need functionality that's not (yet) available
in Curator, these scripts may serve as a good starting point. This collection of
bash scripts for manages [Elasticsearch](http://www.elasticsearch.org) indices.
They are specifically designed around the daily index pattern used in
[Logstash](http://logstash.net).

Support is integrated for uploading backups to S3 using s3cmd.

Each script has samples included, use '-h' or check the source. THe default
index is 'logstash', but this option is configurable with '-g' for 'marvel' or
custom index names.

These are heavily inspired by [a previous collection of
scripts](http://tech.superhappykittymeow.com/?p=296).

### elasticsearch-remove-old-indices.sh

This script generically walks through the indices, sorts them lexicographically,
and deletes anything older than the configured number of indices.

### elasticsearch-close-old-indices.sh

This script generically walks through the indices, sorts them lexicographically,
and closes indices older than the configured number of indices.

### elasticsearch-backup-index.sh

Backup handles making a backup and a restore script for a given index. The
default is yesterday's index, or you can pass a specific date for backup. You
can optionally keep the backup locally, and/or push it to s3. If you want to get
tricky, you can override the s3cmd command, and you could have this script push
the backups to a storage server on your network (or whatever you want, really).

### elasticsearch-restore-index.sh

Restore handles retrieving a backup file and restore script (from S3), and then
executing the restore script locally after download.


## Cron

### Manual

Something like this might be helpful, assuming you placed the scripts in the
/opt/es/ directory (formatted for an /etc/cron.d/ file):

    00 7 * * * root /bin/bash /opt/es/elasticsearch-backup-index.sh -b "s3://es-bucket" -i "/opt/elasticsearch/data/elasticsearch/nodes/0/indices" -c "s3cmd put -c /path/to/.s3cfg"
    00 9 * * * root /bin/bash /opt/es/elasticsearch-remove-old-indices.sh -i 21

### `es-backup-index.sh`

Alternatively @sergedu provided a sample cron script `es-backup-index.sh`.

The es-backup-index script is ready for use, and assuming your setup is consistent, these instructions (included in the script itself) should be enough to get started:

````
# This is a wrapper script for daily run
# i.e. you can run it by cron as follows
## m h  dom mon dow   command
#  11 4 * * * /opt/es/es-backup-index.sh >> /var/log/elasticsearch/esindexbackup.log 
````
