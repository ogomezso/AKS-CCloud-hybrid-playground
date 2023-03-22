#! /bin/bash

set -u -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

kubectl create secret generic password-encoder-secret --from-file ${DIR}/password-encoder.txt