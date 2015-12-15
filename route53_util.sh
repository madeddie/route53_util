#!/bin/bash
#
# route53_util.sh
#
# route53_util.sh lookup appdev.io venus.appdev.io
# route53_util.sh <create|upsert|delete> appdev.io venus.appdev.io venus-green.appdev.io CNAME 60 "just because"
#

if [ "$1" = "-v" ]; then
  VERBOSE=true
  shift
fi

if [ "$1" = "lookup" ]; then
  shift
  if [ $# -lt 2 ]; then echo 'Not enough arguments to do lookup'; exit 2; fi
  
  ZONE_NAME=$1
  RECORD=$2
  ESCAPED_RECORD=${2//\*/\052}
  if [ "$VERBOSE" = "true" ]; then
    VERBOSE_OUTPUT="[].Name, [].TTL, 'IN', [].Type, "
  fi
  OUTPUT_FILTER="| [${VERBOSE_OUTPUT}[?AliasTarget].AliasTarget.DNSName, [?ResourceRecords].ResourceRecords[0].Value][]"
  ZONE_ID=$(aws --output text route53 list-hosted-zones --query "HostedZones[?Name=='${ZONE_NAME}.'][Id]")
  output=$(aws --output text route53 list-resource-record-sets \
    --hosted-zone-id="$ZONE_ID" \
    --start-record-name "$ESCAPED_RECORD" \
    --max-items=1 \
    --query "ResourceRecordSets[?Name=='${ESCAPED_RECORD}.']${OUTPUT_FILTER}")

  if [ ! "$output" ]; then 
    echo "Record not found"
  else
    echo "$output"
  fi


elif [ "$1" = "create" ] || [ "$1" = "upsert" ] || [ "$1" = "delete" ]; then
  ACTION=$(echo "$1" | tr '[:lower:]' '[:upper:]')
  shift
  if [ $# -lt 3 ]; then echo 'Not enough arguments'; exit 2; fi

  ZONE_NAME=$1
  RECORD=$2
  VALUE=$3
  TYPE="${4:-CNAME}"
  TTL=${5:-60}
  COMMENT="updated via script on $(date '+%x %X')"
  
  TMPFILE=$(mktemp /tmp/temporary-file.XXXXXXXX)
  ZONE_ID=$(aws --output text route53 list-hosted-zones --query "HostedZones[?Name=='${ZONE_NAME}.'][Id]")
  cat > "$TMPFILE" << EOF 
{ 
  "Comment": "${COMMENT}", 
  "Changes": [ 
    { 
      "Action": "${ACTION}", 
      "ResourceRecordSet": { 
        "Name": "${RECORD}", 
        "Type": "${TYPE}", 
        "TTL": ${TTL}, 
        "ResourceRecords": [ 
          { 
            "Value": "${VALUE}" 
          } 
        ] 
      } 
    } 
  ] 
}
EOF
  
  aws route53 change-resource-record-sets \
    --hosted-zone-id="$ZONE_ID" \
    --change-batch file://"${TMPFILE}"
  
  rm "${TMPFILE}"

else
  echo 'Commands to use: lookup, create, upsert and delete'
fi
