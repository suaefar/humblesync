#!/bin/bash

# configuration
# set your username and password
USER=''
PASS=''
HUMBLE_URL="https://www.humblebundle.com"

# help
if [ "$1" == "--help" ]
then
  echo ""
  echo "./humblesync.sh [DIRECTORY] [KEY1 KEY2 ...]"
  echo "  DIRECTORY defaults to the current directory"
  echo "  if no keys are provided all available keys are retrieved"
  echo ""
  exit 0
fi

# get arguments
DATADIR="$1"
shift
KEYS=($@)

# check if username and password are set
if [ -z "$USER" ] || [ -z "$PASS" ]
then
  echo "set your username and password by editing this script"
  exit 1
fi

# check for required programs
MISSING=""
$(jq --version >/dev/null 2>&1) || MISSING="$MISSING jq"
$(curl --version >/dev/null 2>&1) || MISSING="$MISSING curl"
if [ -n "$MISSING" ]
then
  echo >&2 "please install the following programs:$MISSING"
  exit 1
fi

# functions
GET() {
  local FILENAME="$1"
  shift
  curl -o "$FILENAME" -s --cookie ./logincookie \
  --header "Accept: application/json" \
  --header "Accept-Charset: utf-8" \
  --header "Keep-Alive: true" \
  --header "X-Requested-By: hb_android_app" \
  --header "User-Agent: Apache-HttpClient/UNAVAILABLE (java 1.4)" \
  $@
}

ALIVE() {
  local LOGINCHECK=$(GET - "$HUMBLE_URL/api/v1/" | wc -l)
  [ $LOGINCHECK -gt 0  ] && return 0
  return 1
}

LOGIN() {
  curl --cookie-jar ./logincookie \
  --header "Accept: application/json" \
  --header "Accept-Charset: utf-8" \
  --header "Keep-Alive: true" \
  --header "X-Requested-By: hb_android_app" \
  --header "User-Agent: Apache-HttpClient/UNAVAILABLE (java 1.4)" \
  --data "username=$USER" \
  --data "password=$PASS" \
  "${HUMBLE_URL}/login" &> /dev/null
}

CONNECT() {
  ALIVE || LOGIN
  ALIVE || echo >&2 "login failed"
}

extract() {
 jq  ".subproducts[].downloads[].download_struct[] | [ .md5, .file_size, .url.web ]" | \
  sed -E -e 's/^[ ]*"?//g' \
  -e 's/"?,?[ ]*$//g' \
  -e 's/^\]/##NEWLINEPLACEHOLDER##/g' \
  -e '/^[ ]*\[[ ]*$/d' | \
  tr "\n" " " | \
  sed -E -e 's/[ ]*##NEWLINEPLACEHOLDER##[ ]*/\n/g'
}

getkeys() {
  CONNECT
  GET - "$HUMBLE_URL/api/v1/user/order" | \
  grep -o -E '"[A-Za-z0-9]{16}"' | \
  tr -d '"'
}

getfiles() {
  local KEY="$1"
  CONNECT
  GET - "$HUMBLE_URL/api/v1/order/${KEY}" | extract | \
  while read line
  do
    local ITEM=($line)
    local MD5="${ITEM[0]}"
    local SIZE="${ITEM[1]}"
    local URL="${ITEM[2]}"
    local NAME=$(echo "$URL" | \
      grep -o '/[^/]\+$' | \
      sed -E -e 's/\?.*//g' -e 's/^\///g')
    local FILENAME="$DATADIR/$NAME"
    if [ -n "$FILENAME" ] && [ "$SIZE" != "null" ]
    then
      echo "    '${NAME}' ($SIZE b)"
      if [ -e "$FILENAME" ] && [ "$SIZE" == $(stat -c%s "$FILENAME") ]
      then
        echo "      exists"
        continue
      fi
      if ! ALIVE
      then
        echo "  logout"
        return 1
      fi
      echo "      download"
      GET "$FILENAME" "${URL}"
      if [ -e "$FILENAME" ]
      then
        echo "        done"
        local SIZECHECK=$(stat -c%s "$FILENAME")
        if [ "$SIZE" == "$SIZECHECK" ]
        then
          echo "        size:$SIZECHECK b ok"
          local MD5CHECK=$(md5sum "$FILENAME" | cut -d" " -f1)
          if [ "$MD5" == "$MD5CHECK" ]
          then
            echo "        md5sum:$MD5CHECK ok"
          else
            echo "        md5sum:$MD5CHECK wrong. should be $MD5"
          fi
        else
          echo "        size:$SIZECHECK b wrong. should be $SIZE b"
        fi
      else
        echo "        error"
      fi
    fi
  done && return 0
  return 1
}

# main
[ -n "$DATADIR" ] || DATADIR='.'
[ ${#KEYS[@]} -gt 0 ] || KEYS=($(getkeys))
echo "sync ${#KEYS[@]} key(s)"
mkdir -p "$DATADIR"
for KEY in ${KEYS[@]}
do
  while true
  do
    echo "  '$KEY'"
    getfiles "$KEY" && break
    echo "  retry"
  done
done

