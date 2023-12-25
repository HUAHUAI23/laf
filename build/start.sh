echo "API_DOMAIN: $API_DOMAIN"
echo "RUNTIME_DOMAIN: $RUNTIME_DOMAIN"
echo "WEBSITE_DOMAIN: $WEBSITE_DOMAIN"
echo "WEB_DOMAIN: $WEB_DOMAIN"
echo "OSS_DOMAIN:$OSS_DOMAIN"
echo "OSS_CONSOLE_DOMAIN:$OSS_CONSOLE_DOMAIN"

# Function to check domain availability
check_domain() {
    if ! host "$1"; then
        echo "Domain $1 is not available"
        exit 1
    else
        echo "Domain $1 is available"
    fi
}

# Check each domain
check_domain $API_DOMAIN
check_domain $RUNTIME_DOMAIN
check_domain $WEBSITE_DOMAIN
check_domain $WEB_DOMAIN
check_domain $OSS_DOMAIN
check_domain $OSS_CONSOLE_DOMAIN

# *************** Environment Variables ************** #

## envs - global
EXTERNAL_HTTP_SCHEMA=${EXTERNAL_HTTP_SCHEMA:-https}
INTERNAL_HTTP_SCHEMA=${INTERNAL_HTTP_SCHEMA:-http}

NAMESPACE=${NAMESPACE:-laf-system}
PASSWD_OR_SECRET=$(tr -cd 'a-z0-9' </dev/urandom | head -c32)

ENABLE_MONITOR=${ENABLE_MONITOR:-true}

# *************** Deployments **************** #

## 0. create namespace
kubectl create namespace ${NAMESPACE} || true

## 1. install mongodb
set -e
set -x

DATABASE_URL="mongodb://${DB_USERNAME:-admin}:${PASSWD_OR_SECRET}@mongodb-0.mongo.${NAMESPACE}.svc.cluster.local:27017/sys_db?authSource=admin&replicaSet=rs0&w=majority"
helm install mongodb -n ${NAMESPACE} \
    --set db.username=${DB_USERNAME:-admin} \
    --set db.password=${PASSWD_OR_SECRET} \
    --set storage.size=${DB_PV_SIZE:-5Gi} \
    ./charts/mongodb

## 3. install prometheus
PROMETHEUS_URL=http://prometheus-operated.${NAMESPACE}.svc.cluster.local:9090
if [ "$ENABLE_MONITOR" = "true" ]; then
    sed -e "s/\$NAMESPACE/$NAMESPACE/g" \
        -e "s/\$PROMETHEUS_PV_SIZE/${PROMETHEUS_PV_SIZE:-20Gi}/g" \
        prometheus-helm.yaml >prometheus-helm-with-values.yaml

    helm install prometheus --version 48.3.3 -n ${NAMESPACE} \
        -f ./prometheus-helm-with-values.yaml \
        ./charts/kube-prometheus-stack

    helm install prometheus-mongodb-exporter --version 3.2.0 -n ${NAMESPACE} \
        --set mongodb.uri=${DATABASE_URL} \
        --set serviceMonitor.enabled=true \
        --set serviceMonitor.additionalLabels.release=prometheus \
        --set serviceMonitor.additionalLabels.namespace=${NAMESPACE} \
        ./charts/prometheus-mongodb-exporter
fi

## 4. install minio
MINIO_ROOT_ACCESS_KEY=minio-root-user
MINIO_ROOT_SECRET_KEY=$PASSWD_OR_SECRET
MINIO_DOMAIN=$OSS_DOMAIN
MINIO_EXTERNAL_ENDPOINT="${EXTERNAL_HTTP_SCHEMA}://${MINIO_DOMAIN}"
MINIO_INTERNAL_ENDPOINT="${INTERNAL_HTTP_SCHEMA}://minio.${NAMESPACE}.svc.cluster.local:9000"

helm install minio -n ${NAMESPACE} \
    --set rootUser=${MINIO_ROOT_ACCESS_KEY} \
    --set rootPassword=${MINIO_ROOT_SECRET_KEY} \
    --set persistence.size=${OSS_PV_SIZE:-3Gi} \
    --set domain=${MINIO_DOMAIN} \
    --set consoleHost=${OSS_CONSOLE_DOMAIN} \
    --set metrics.serviceMonitor.enabled=${ENABLE_MONITOR} \
    --set metrics.serviceMonitor.additionalLabels.release=prometheus \
    --set metrics.serviceMonitor.additionalLabels.namespace=${NAMESPACE} \
    ./charts/minio

## 5. install laf-server
SERVER_JWT_SECRET=$PASSWD_OR_SECRET
RUNTIME_EXPORTER_SECRET=$PASSWD_OR_SECRET
helm install server -n ${NAMESPACE} \
    --set databaseUrl=${DATABASE_URL} \
    --set jwt.secret=${SERVER_JWT_SECRET} \
    --set apiServerHost=${API_DOMAIN} \
    --set apiServerUrl=${EXTERNAL_HTTP_SCHEMA}://${API_DOMAIN} \
    --set siteName=${WEB_DOMAIN} \
    --set default_region.fixed_namespace=${NAMESPACE} \
    --set default_region.database_url=${DATABASE_URL} \
    --set default_region.minio_domain=${MINIO_DOMAIN} \
    --set default_region.minio_external_endpoint=${MINIO_EXTERNAL_ENDPOINT} \
    --set default_region.minio_internal_endpoint=${MINIO_INTERNAL_ENDPOINT} \
    --set default_region.minio_root_access_key=${MINIO_ROOT_ACCESS_KEY} \
    --set default_region.minio_root_secret_key=${MINIO_ROOT_SECRET_KEY} \
    --set default_region.runtime_domain=${RUNTIME_DOMAIN} \
    --set default_region.website_domain=${WEBSITE_DOMAIN} \
    --set default_region.tls.enabled=false \
    --set default_region.runtime_exporter_secret=${RUNTIME_EXPORTER_SECRET} \
    $([ "$ENABLE_MONITOR" = "true" ] && echo "--set default_region.prometheus_url=${PROMETHEUS_URL}") \
    ./charts/laf-server

## 6. install laf-web
helm install web -n ${NAMESPACE} \
    --set domain=${WEB_DOMAIN} \
    ./charts/laf-web
