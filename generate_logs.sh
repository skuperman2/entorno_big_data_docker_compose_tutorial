#!/bin/bash
# Generador simple de logs tipo Apache

LOGFILE="access.log"
URLS=("/" "/productos" "/contacto" "/carrito" "/checkout")
CODES=("200" "200" "200" "404" "500" "302")
METHODS=("GET" "POST")
AGENTS=("Mozilla/5.0" "curl/7.68.0" "PostmanRuntime/7.29.0")

> $LOGFILE

for i in {1..500}; do
  IP="$((RANDOM%255)).$((RANDOM%255)).$((RANDOM%255)).$((RANDOM%255))"
  DATE=$(date -d "now -$((RANDOM%86400)) seconds" "+%d/%b/%Y:%H:%M:%S %z")
  METHOD=${METHODS[$RANDOM % ${#METHODS[@]}]}
  URL=${URLS[$RANDOM % ${#URLS[@]}]}
  CODE=${CODES[$RANDOM % ${#CODES[@]}]}
  SIZE=$((RANDOM % 5000 + 200))
  AGENT=${AGENTS[$RANDOM % ${#AGENTS[@]}]}

  echo "$IP - - [$DATE] \"$METHOD $URL HTTP/1.1\" $CODE $SIZE \"-\" \"$AGENT\"" >> $LOGFILE
done

echo "Archivo $LOGFILE generado con 500 líneas."
