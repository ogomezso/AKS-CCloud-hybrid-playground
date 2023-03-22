#! /bin/bash

set -u -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

kubectl -n confluent create secret generic ccloud-tls-certs --from-file=${DIR}/fullchain.pem --from-file=${DIR}/cacerts.pem