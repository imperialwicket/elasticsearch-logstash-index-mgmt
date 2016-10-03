#!/usr/bin/env bash
#
# Delete logstash format indices from elasticsearch maintaining only a
# specified number.
#
#   Inspiration:
#     https://github.com/imperialwicket/elasticsearch-logstash-index-mgmt/blob/master/elasticsearch-remove-old-indices.sh
#
# Must have access to the specified elasticsearch node.

usage()
{
cat << EOF

elasticsearch-remove-expired-indices.sh

Delete all indices older than a date.


USAGE: ./elasticsearch-remove-expired-indices.sh [OPTIONS]

OPTIONS:
  -h    Show this message
  -d    Expiration date (YYYY-MM-dd) from when we should start deleting the indices (default: 3 months ago)
  -e    Elasticsearch URL (default: http://localhost:9200)
  -g    Consistent index name (default: logstash)
  -o    Output actions to a specified file

EXAMPLES:

  ./elasticsearch-remove-old-indices.sh

    Connect to http://localhost:9200 and get a list of indices matching
    'logstash'. Keep the indices from less than 3 months, delete any others.

  ./elasticsearch-remove-old-indices.sh -e "http://es.example.com:9200" \
  -d 1991-04-25 -g my-logs -o /mnt/es/logfile.log

    Connect to http://es.example.com:9200 and get a list of indices matching
    'my-logs'. Keep the indices created after the 25 april 1991, delete any others.
    Output index deletes to /mnt/es/logfile.log.

EOF
}

# Defaults
ELASTICSEARCH="http://localhost:9200"
DATE=$(date  --date="3 months ago" +"%Y%m%d")
INDEX_NAME="logstash"
LOGFILE=/dev/null

# Validate numeric values
RE_DATE="^[0-9]{4}-((0[0-9])|(1[0-2]))-(([0-2][0-9])|(3[0-1]))+$"

while getopts ":d:e:g:o:h" flag
do
  case "$flag" in
    h)
      usage
      exit 0
      ;;
    d)
      if [[ $OPTARG =~ $RE_DATE ]]; then
        DATE=$OPTARG
      else
        ERROR="${ERROR}Expiration date must be YYYY-MM-dd.\n"
      fi
      ;;
    e)
      ELASTICSEARCH=$OPTARG
      ;;
    g)
      INDEX_NAME=$OPTARG
      ;;
    o)
      LOGFILE=$OPTARG
      ;;
    ?)
      usage
      exit 1
      ;;
  esac
done

# If we have errors, show the errors with usage data and exit.
if [ -n "$ERROR" ]; then
  echo -e $ERROR
  usage
  exit 1
fi

# Get the indices from elasticsearch
INDICES_TEXT=`curl -s "$ELASTICSEARCH/_cat/indices?v" | awk '/'$INDEX_NAME'/{match($0, /[:blank]*('$INDEX_NAME'.[^ ]+)[:blank]*/, m); print m[1];}' | sort -r`

if [ -z "$INDICES_TEXT" ]; then
  echo "No indices returned containing '$GREP' from $ELASTICSEARCH."
  exit 1
fi

# If we are logging, make sure we have a logfile TODO - handle errors here
if [ -n "$LOGFILE" ] && ! [ -e $LOGFILE ]; then
  touch $LOGFILE
fi

# Delete indices
declare -a INDEX=($INDICES_TEXT)
  for index in ${INDEX[@]};do
    # We don't want to accidentally delete everything
    if [ -n "$index" ]; then
        INDEX_DATE=$(echo $index | sed -n 's/.*\([0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}\).*/\1/p'| sed 's/\./-/g')
        if [ $(date  -d $DATE +"%Y%m%d") -ge $(date -d $INDEX_DATE +"%Y%m%d")  ]; then
            echo `date "+[%Y-%m-%d %H:%M] "`" Deleting index: $index." >> $LOGFILE
            curl -s -XDELETE "$ELASTICSEARCH/$index/" >> $LOGFILE
        fi
    fi
  done
exit 0
