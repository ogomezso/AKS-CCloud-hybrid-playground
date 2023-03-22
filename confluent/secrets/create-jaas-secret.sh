#! /bin/bash

set -u -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

kubectl -n confluent create secret generic jaasconfig-ccloud --from-file=plain-jaas.conf=${DIR}/jaas.txt