# DC Services Containerization

This tutorial provides a step-by-step guide on containerizing DC Services using the
app-distributed-cloud prototype. The objective is to ensure the interaction between
the dcmanager-api pod and the dcmanager-manager pod while integrating essential
platform components such as dcmanager-client, keystone, rabbitmq, and certificates.

This use the minikube build environment for WRCP: <https://confluence.wrs.com/pages/viewpage.action?pageId=165764450>

Recommended: have all packages built before setting up the new app-distributed-cloud

## Configure prototype in the WRCP build environment

- Prototype: `/folk/cgts/users/mpeters/design/platform/distcloud/app-distributed-cloud/`
- Copy app-distributed-cloud directory to `$MY_REPO/stx`
- Add app-distributed-cloud to manifest `$MY_REPO/../.repo/manifests/default.xml`

  ```xml
  <project remote="starlingx"  name="app-distributed-cloud.git"               path="cgcs-root/stx/app-distributed-cloud"/>
  ```

- Add app-distributed-cloud to project.list: $MY_REPO/../.repo/project.list

cgcs-root/stx/app-distributed-cloud

## Build Required Packages

Note.: If package builds fail, you can retrieve the *.deb file and rebuild it:

`localdisk/loadbuild/jenkins/wrcp-master-debian/latest_build/export/outputs/aptly/deb-local-build/pool/main/<initial_letter>/<package>/<package.deb>`

Copy to `aptly/public/deb-local-build-{}/pool/main/` and `localdisk/loadbuild/<user>/wrcp-env/std` in your env

- Required packages:

```bash
build-pkgs -p cgcs-patch,cgts-client,distributedcloud-client,distributedcloud,fm-api,fm-common,fm-rest-api,nfv,nova-api-proxy,pci-irq-affinity-agent,python-fmclient,python3-networking-avs,python3-oidcauthtools,python3-vswitchclient,software-client,software,sysinv,tsconfig
```

- Build Distributed Cloud application bundle

```bash
build-pkgs -c -p python3-k8sapp-distributed-cloud,stx-distributed-cloud-helm
dpkg -x /localdisk/loadbuild/$USER/stx-debian/std/stx-distributed-cloud-helm/stx-distributed-cloud-helm_1.0-1.stx.0_amd64.deb tmp
cp tmp/usr/local/share/applications/helm/distributed-cloud-24.09-0.tgz to the subcloud
```

## Build wheels

```bash
$MY_REPO/build-tools/build-wheels/build-wheel-tarball.sh --keep-image --cache --os debian
```

## Container image build: <https://confluence.wrs.com/display/CE/How+to+build+docker+images>

```bash
BUILD_OS=debian
BUILD_STREAM=stable
BRANCH=master
# This is the image base build on the local(check it with docker image ls), or we can use daily built images as:
# starlingx/stx-debian:master-stable-latest or starlingx/stx-debian:master-stable-<date>
BASE_IMAGE=starlingx/stx-debian:master-stable-latest
WHEELS=$MY_WORKSPACE/std/build-wheels-debian-stable/stx-debian-stable-wheels.tar
DOCKER_USER=yjiang1
DOCKER_REGISTRY=admin-2.cumulus.wrs.com:30093

# Pull base image
docker pull $BASE_IMAGE

# Login to the registry for pushing the container image
docker login -u ${DOCKER_USER} ${DOCKER_REGISTRY}

$MY_REPO/build-tools/build-docker-images/build-stx-images.sh \
    --os ${BUILD_OS} \
    --stream ${BUILD_STREAM} \
    --base ${BASE_IMAGE} \
    --wheels ${WHEELS} \
    --user ${DOCKER_USER} \
    --registry ${DOCKER_REGISTRY} \
    --no-pull-base --cache \
    --push --latest \
    --only "stx-distributed-cloud"
```

## Build WRCP iso

```bash
build-image
```

## Disable Service Management

With the new WRCP ISO installed, you need to disable the DCManager services that are being containerized.

```bash
source /etc/platform/openrc

sudo sm-unmanage service dcagent-api
sudo sm-unmanage service dcdbsync-api


sudo pkill -f ^".*/bin/dcagent.*"
sudo pkill -f ^".*/bin/dcdbsync.*"
```

## Platform Setup

```bash
system host-label-assign controller-0 starlingx.io/subcloud=enabled
```

## Create the namespace and default registry (avoid issues)

```bash
# Create distributed-cloud namespace

kubectl create namespace distributed-cloud

# Create default-registry-key secret | if using registry.local:9001

kubectl create secret docker-registry default-registry-key \
  --docker-server=registry.local:9001 \
  --docker-username=admin \
  --docker-password=${OS_PASSWORD} \
  --namespace=distributed-cloud

# Create ca-cert secret to allow SSL

sudo cp /etc/ssl/certs/ca-certificates.crt /home/sysadmin
sudo chown sysadmin:sys_protected /home/sysadmin/ca-certificates.crt
kubectl -n distributed-cloud create secret generic root-ca   --from-file=ca.crt=/home/sysadmin/ca-certificates.crt
```

## Distributed Cloud Application Deployment (development)

```bash
# Configure Docker Image (using Matt's image)

DOCKER_REGISTRY=admin-2.cumulus.wrs.com:30093
DOCKER_USER=yjiang1
DOCKER_ADMIN_IMAGE=${DOCKER_REGISTRY}/${DOCKER_USER}/stx-distributed-cloud:dev-debian-stable-latest
DOCKER_IMAGE=registry.local:9001/docker.io/starlingx/stx-distributed-cloud:master-debian-stable-latest

sudo docker login registry.local:9001

sudo docker image pull ${DOCKER_ADMIN_IMAGE}
sudo docker image tag ${DOCKER_ADMIN_IMAGE} ${DOCKER_IMAGE}
sudo docker image push ${DOCKER_IMAGE}
```

```bash
system application-upload distributed-cloud-24.09-0.tgz

# Set Password Variables

ADMIN_KS_PASSWORD=$(keyring get CGCS admin)
DCAGENT_KS_PASSWORD=$(keyring get dcagent services)

cat<<EOF>dcagent.yaml
images:
  tags:
    dcagent: ${DOCKER_IMAGE}
    ks_user: ${DOCKER_IMAGE}
    ks_service: ${DOCKER_IMAGE}
    ks_endpoints: ${DOCKER_IMAGE}
  pullPolicy: Always
pod:
  image_pull_secrets:
    default:
      - name: default-registry-key
  tolerations:
    dcagent:
      enabled: true
conf:
  dcagent:
    DEFAULT:
      log_config_append: /etc/dcagent/logging.conf
      auth_strategy: keystone
      workers: 1
    keystone_authtoken:
      auth_uri: http://controller.internal:5000
      auth_url: http://controller.internal:5000
      auth_type: password
      region_name: ${OS_REGION_NAME}
      username: dcagent
      password: ${DCAGENT_KS_PASSWORD}
      project_name: services
      user_domain_name: Default
      project_domain_name: Default
    endpoint_cache:
      auth_uri: http://controller.internal:5000/v3
      auth_plugin: password
      region_name: ${OS_REGION_NAME}
      username: dcagent
      password: ${DCAGENT_KS_PASSWORD}
      user_domain_name: Default
      project_name: services
      project_domain_name: Default
      http_connect_timeout: 15
dependencies:
  static:
    api:
      jobs:
        - dcagent-ks-user
        - dcagent-ks-service
        - dcagent-ks-endpoints
    ks_endpoints:
      jobs:
        - dcagent-ks-user
        - dcagent-ks-service
endpoints:
  cluster_domain_suffix: cluster.local
  identity:
    name: keystone
    auth:
      admin:
        username: admin
        password: ${ADMIN_KS_PASSWORD}
        region_name: ${OS_REGION_NAME}
        project_name: admin
        user_domain_name: Default
        project_domain_name: Default
      dcagent:
        role: admin
        username: dcagent
        password: ${DCAGENT_KS_PASSWORD}
        region_name: ${OS_REGION_NAME}
        project_name: services
        user_domain_name: Default
        project_domain_name: Default
    hosts:
      default: keystone-api
      public: keystone
    host_fqdn_override:
      default: controller.internal
    path:
      default: /v3
    scheme:
      default: http
    port:
      api:
        default: 80
        internal: 5000
  dcagent:
    name: dcagent
    hosts:
      default: dcagent-api
      public: dcagent
    host_fqdn_override:
      default: null
    path:
      default: /v1
    scheme:
      default: 'http'
    port:
      api:
        default: 8325
        public: 80

EOF

```

```bash
system helm-override-update distributed-cloud dcagent distributed-cloud --values dcagent.yaml

system helm-override-show distributed-cloud dcagent distributed-cloud

# Possible issue with ceph-pool-kube-rbd secret
kubectl create secret generic ceph-pool-kube-rbd --namespace=kube-system

# Apply app-distributed-cloud
system application-apply distributed-cloud
system application-show distributed-cloud

# To remove
system application-remove distributed-cloud
system application-delete distributed-cloud
```

## Check dcagent endpoints

```bash
openstack endpoint list | grep dcagent
```

## Check if dcagent-api endpoint works

```bash
kubectl get svc dcagent-api -n distributed-cloud
kubectl get endpoints dcagent-api -n distributed-cloud

# Get Token
openstack token issue

# Set TOEKN=token ID get from the previous step
curl -v http://<endpoint>/v1/dcaudit -X PATCH -H "Content-Type: application/json" -H "X-Auth-Token:$token" -d '{"base_audit": ""}'
```

## Distributed Cloud Helm Deployment (manual)

- Create the helm chart

```bash
# inside app-distributed-cloud/stx-distributed-cloud-helm/stx-distributed-cloud-helm/helm-charts/dcmanager
helm package .
helm install dcagent dcagent-0.1.0.tgz --namespace distributed-cloud --values dcagent.yaml
```

## Check secrets

kubectl -n distributed-cloud get secret dcagent-etc --output="jsonpath={.data.dcagent\.conf}" | base64 --decode
kubectl -n distributed-cloud get secret dcagent-keystone-admin --output="jsonpath={.data.OS_PASSWORD}" | base64 --decode

## Check Logs

kubectl -n distributed-cloud logs -l application=dcagent,component=api

helm status --show-resources dcagent --namespace distributed-cloud

## Create a load balancer with helm
```bash
cat<<EOF>nginx.yaml
controller:
  ingressClassResource:
    name: dc-nginx
    controllerValue: "k8s.io/dc-nginx"
    enabled: true
  ingressClass: dc-nginx
  hostNetwork: true
  service:
    enabled: false
  containerPort:
    http: 8325
    https: 8327
  extraArgs:
    http-port: "8325"
    https-port: "8327"
    default-server-port: "81"
    status-port: "10251"
    stream-port: "10252"
    profiler-port: "10253"
    healthz-port: "10255"
EOF
```

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install dc-nginx ingress-nginx/ingress-nginx \
  --namespace distributed-cloud \
  --set controller.service.type=LoadBalancer \
  --set controller.service.httpPort.port=8325 \
  --set controller.service.httpPort.targetPort=8325
  --set controller.ingressClassResource.name=dc-nginx
```
