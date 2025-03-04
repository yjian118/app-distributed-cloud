#
# Copyright (c) 2025 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

from . import base

from k8sapp_distributed_cloud.common import constants as app_constants


class DCAgentHelm(base.DistributedCloudHelm):

    @property
    def CHART(self):
        return app_constants.HELM_CHART_DCAGENT

    @property
    def HELM_RELEASE(self):
        return app_constants.FLUXCD_HELM_RELEASE_DCAGENT
