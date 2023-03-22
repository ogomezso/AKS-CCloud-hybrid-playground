#! /bin/bash

set -u -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

kubectl -n confluent create secret generic ccloud-sr-credentials --from-file=basic.txt=${DIR}/basic-sr.txt