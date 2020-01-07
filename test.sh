#!/bin/bash

set -e -o pipefail

# Usage
#    ./test.sh <VMID>


ONE_AUTH_STRING="oneadmin:oneadmin"
ONE_VNC=${ONE_VNC:-http://127.0.0.1:2644/RPC2}

curl -H "Content-Type: text/xml" -X GET \
  -d "<?xml version='1.0'?>
      <methodCall>
        <methodName>one.vm.vnc</methodName>
        <params>
          <param>
            <value><string>$ONE_AUTH_STRING</string></value>
          </param>
          <param>
            <value><i4>${1:-155}</i4></value>
          </param>
        </params>
      </methodCall>" $ONE_VNC | tee test.out
xmllint -format test.out

if [ $? -ne 0 ]; then
  echo "error: request terminated with error"
  exit 1
fi 

