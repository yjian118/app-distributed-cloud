#!/bin/bash

{{/*
#
# SPDX-License-Identifier: Apache-2.0
#
*/}}

set -ex

python /var/lib/openstack/bin/dcmanager-api --config-file=/etc/dcmanager/dcmanager.conf
