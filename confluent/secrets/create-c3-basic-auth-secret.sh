#! /bin/bash

set -u -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

kubectl -n confluent create secret generic c3-basic-secret --from-file=basic.txt=${DIR}/basic-c3.txt