#!/bin/bash

{{/*
#
# SPDX-License-Identifier: Apache-2.0
#
*/}}

set -ex

python /var/lib/openstack/bin/dcagent-api --config-file=/etc/dcagent/dcagent.conf
