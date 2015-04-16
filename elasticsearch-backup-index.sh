#!/bin/bash
#
# elasticsearch-backup-index.sh
#
# Push logstash index from yesterday to s3 with an accompanying restore script.
#   http://logstash.net
#   http://www.elasticsearch.org
#   https://github.com/s3tools/s3cmd | http://s3tools.org/s3cmd
#
#   Inspiration:
#     http://tech.superhappykittymeow.com/?p=296
#
# Must run on an elasticsearch node, and expects to find the index on this node.

usage()
{
cat << EOF

elasticsearch-backup-index.sh

Create a restorable backup of an elasticsearch index (assumes Logstash format
indexes), and upload it to an existing S3 bucket. The default backs up an
index from yesterday. Note that this script itself does not restart
elasticsearch - the restore script that is generated for each backup will
restart elasticsearch after restoring an archived index.

USAGE: ./elasticsearch-backup-index.sh -b S3_BUCKET -i INDEX_DIRECTORY [OPTIONS]

OPTIONS:
  -h    Show this message
  -b    S3 path for backups (Required)
  -g    Consistent index name (default: logstash)
  -i    Elasticsearch index directory (Required)
  -d    Backup a specific date (format: YYYY.mm.dd)
  -c    Command for s3cmd (default: s3cmd put)
  -t    Temporary directory for archiving (default: /tmp)
  -p    Persist local backups, by default backups are not kept locally
  -s    Shards (default: 5)
  -r    Replicas (default: 0)
  -e    Elasticsearch URL (default: http://localhost:9200)
  -n    How nice tar must be (default: 19)
  -u    Restart command for elastic search (default 'service elasticsearch restart')

EXAMPLES:

  ./elasticsearch-backup-index.sh -b "s3://someBucket" \
  -i "/usr/local/elasticsearch/data/node/0/indices"

    This uses http://localhost:9200 to connect to elasticsearch and backs up
    the index from yesterday (based on system time, be careful with timezones)

  ./elasticsearch-backup-index.sh -b "s3://bucket" -i "/mnt/es/data/node/0/indices" \
  -d "2013.05.21" -c "/usr/local/bin/s3cmd put" -t "/mnt/es/backups" \
  -g my_index -u "service es restart" -e "http://127.0.0.1:9200" -p

    Connect to elasticsearch using 127.0.0.1 instead of localhost, backup the
    index "my_index" from 2013.05.21 instead of yesterday, use the s3cmd in /usr/local/bin
    explicitly, store the archive and restore script in /mnt/es/backups (and
    persist them) and use 'service es restart' to restart elastic search.

EOF
}

if [ "$USER" != 'root' ] && [ "$LOGNAME" != 'root' ]; then
  # I don't want to troubleshoot the permissions of others
  echo "This script must be run as root."
  exit 1
fi

# Defaults
S3CMD="s3cmd put"
TMP_DIR="/tmp"
SHARDS=5
REPLICAS=0
ELASTICSEARCH="http://localhost:9200"
NICE=19
RESTART="service elasticsearch restart"

# Validate shard/replica values
RE_D="^[0-9]+$"

while getopts ":b:i:d:c:g:t:p:s:r:e:n:u:h" flag
do
  case "$flag" in
    h)
      usage
      exit 0
      ;;
    b)
      S3_BASE=$OPTARG
      ;;
    i)
      INDEX_DIR=$OPTARG
      ;;
    d)
      DATE=$OPTARG
      ;;
    c)
      S3CMD=$OPTARG
      ;;
    g)
      INAME=$OPTARG
      ;;
    t)
      TMP_DIR=$OPTARG
      ;;
    p)
      PERSIST=1
      ;;
    s)
      if [[ $OPTARG =~ $RE_D ]]; then
        SHARDS=$OPTARG
      else
        ERROR="${ERROR}Shards must be an integer.\n"
      fi
      ;;
    r)
      if [[ $OPTARG =~ $RE_D ]]; then
        REPLICAS=$OPTARG
      else
        ERROR="${ERROR}Replicas must be an integer.\n"
      fi
      ;;
    e)
      ELASTICSEARCH=$OPTARG
      ;;
    n)
      if [[ $OPTARG =~ $RE_D ]]; then
        NICE=$OPTARG
      fi
      # If nice is not an integer, just use default
      ;;
    u)
      RESTART=$OPTARG
      ;;
    ?)
      usage
      exit 1
      ;;
  esac
done

# We need an S3 base path
if [ -z "$S3_BASE" ]; then
  ERROR="${ERROR}Please provide an s3 bucket and path with -b.\n"
fi

# We need an elasticsearch index directory
if [ -z "INDEX_DIR" ]; then
  ERROR="${ERROR}Please provide an Elasticsearch index directory with -i.\n"
fi

# If we have errors, show the errors with usage data and exit.
if [ -n "$ERROR" ]; then
  echo -e $ERROR
  usage
  exit 1
fi

if [ -z "$INAME" ]; then
  INAME="logstash"
fi

# Default logstash index naming is hardcoded, as are YYYY-mm container directories.
if [ -n "$DATE" ]; then
  INDEX="$INAME-$DATE"
  YEARMONTH=${DATE//\./-}
  YEARMONTH=${YEARMONTH:0:7}
else
  INDEX=`date --date='yesterday' +"$INAME-%Y.%m.%d"`
  YEARMONTH=`date --date='yesterday' +"%Y-%m"`
fi
S3_TARGET="$S3_BASE/$YEARMONTH"

# Make sure there is an index
if ! [ -d $INDEX_DIR/$INDEX ]; then
  echo "The index $INDEX_DIR/$INDEX does not appear to exist."
  exit 1
fi

# Get metadata from elasticsearch
INDEX_MAPPING=`curl -s -XGET "$ELASTICSEARCH/$INDEX/_mapping"`
SETTINGS="{\"settings\":{\"number_of_shards\":$SHARDS,\"number_of_replicas\":$REPLICAS},\"mappings\":$INDEX_MAPPING}"

# Make the tmp directory if it does not already exist.
if ! [ -d $TMP_DIR ]; then
  mkdir -p $TMP_DIR
fi

# Tar and gzip the index dirextory.
cd $INDEX_DIR
nice -n $NICE tar czf $TMP_DIR/$INDEX.tgz $INDEX
cd - > /dev/null

# Create a restore script for elasticsearch
cat << EOF >> $TMP_DIR/${INDEX}-restore.sh
#!/bin/bash
#
# ${INDEX}-restore.sh - restores elasticsearch index: $INDEX to elasticsearch
#   instance at $ELASTICSEARCH. This script expects to run in the same
#   directory as the $INDEX.tgz file.

# Make sure this index does not exist already
TEST=\`curl -XGET "$ELASTICSEARCH/$INDEX/_status" 2> /dev/null | grep error\`
if [ -z "\$TEST" ]; then
  echo "Index: $INDEX already exists on this elasticsearch node."
  exit 1
fi

# Extract index files
DOWNLOAD_DIR=\`pwd\`
cd $INDEX_DIR
if [ -f \$DOWNLOAD_DIR/$INDEX.tgz ]; then
  # If we have the archive, create the new index in ES
  curl -XPUT '$ELASTICSEARCH/$INDEX/' -d '$SETTINGS' > /dev/null 2>&1
  # Extract the archive in to the INDEX_DIR
  tar xzf \$DOWNLOAD_DIR/$INDEX.tgz
  # Restart elasticsearch to allow it to open the new dir and file data
  $RESTART
  exit 0
else
  echo "Unable to locate archive file \$DOWNLOAD_DIR/$INDEX.tgz."
  exit 1
fi

EOF

# Put archive and restore script in s3.
$S3CMD $TMP_DIR/$INDEX.tgz $S3_TARGET/$INDEX.tgz
$S3CMD $TMP_DIR/$INDEX-restore.sh $S3_TARGET/$INDEX-restore.sh

# cleanup tmp files
if [ -z $PERSIST ]; then
  rm $TMP_DIR/$INDEX.tgz
  rm $TMP_DIR/$INDEX-restore.sh
fi

exit 0
