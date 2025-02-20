#!/bin/bash

{{/*
#
# SPDX-License-Identifier: Apache-2.0
#
*/}}

set -ex

if ! update-ca-certificates; then
    echo "Failed to update CA certificates!" >&2
    exit 1
fi

exec python /var/lib/openstack/bin/dcagent-api --config-file=/etc/dcagent/dcagent.conf
