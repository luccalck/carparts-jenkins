#!/bin/sh
set -eu
set +x
action=${1:?Informe build, publish, homolog ou production}
mkdir -p .release
: "${RELEASE_COMMIT:?Commit ausente}" "${BUILD_NUMBER:?Build ausente}"
tag="${ACR_NAME:?ACR ausente}.azurecr.io/carparts:${BUILD_NUMBER}-${RELEASE_COMMIT}"
if [ "$action" = build ]; then
  docker build --build-arg "COMMIT_SHA=$RELEASE_COMMIT" -t "$tag" .
  exit 0
fi
: "${AZURE_SUBSCRIPTION:?}" "${AZURE_TENANT:?}" "${AZURE_CLIENT_ID:?}" "${AZURE_CLIENT_SECRET:?}" "${RESOURCE_GROUP:?}"
export AZURE_CONFIG_DIR
AZURE_CONFIG_DIR=$(mktemp -d)
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
cleanup() { rm -rf -- "$AZURE_CONFIG_DIR" "$DOCKER_CONFIG"; }
trap cleanup EXIT HUP INT TERM
az login --service-principal --username "$AZURE_CLIENT_ID" --password "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT" --output none
az account set --subscription "$AZURE_SUBSCRIPTION"
case "$action" in
  publish)
    token=$(az acr login --name "$ACR_NAME" --expose-token --query accessToken -o tsv)
    printf '%s' "$token" | docker login "$ACR_NAME.azurecr.io" --username 00000000-0000-0000-0000-000000000000 --password-stdin
    unset token
    docker push "$tag"
    digest=$(az acr repository show --name "$ACR_NAME" --image "carparts:${BUILD_NUMBER}-${RELEASE_COMMIT}" --query digest -o tsv)
    case "$digest" in sha256:*) ;; *) echo 'Digest inválido'; exit 1 ;; esac
    printf '%s.azurecr.io/carparts@%s\n' "$ACR_NAME" "$digest" > .release/image.txt
    cat .release/image.txt
    ;;
  homolog|production)
    image=$(cat .release/image.txt)
    case "$image" in "$ACR_NAME.azurecr.io/carparts@sha256:"*) ;; *) echo 'Imagem inválida'; exit 1 ;; esac
    if [ "$action" = homolog ]; then app=${HOMOLOG_APP:?}; else
      app=${PROD_APP:?}
      : "${APPROVED_BY:?Sem aprovador}" "${APPROVED_AT:?Sem horário de aprovação}"
    fi
    az containerapp show -g "$RESOURCE_GROUP" -n "$app" --query properties.template.containers[0].image -o tsv > ".release/previous-$action.txt"
    az containerapp update -g "$RESOURCE_GROUP" -n "$app" --image "$image" --revision-suffix "b${BUILD_NUMBER}" --output none
    url=$(az containerapp show -g "$RESOURCE_GROUP" -n "$app" --query properties.configuration.ingress.fqdn -o tsv)
    node scripts/smoke.mjs "https://$url" "$RELEASE_COMMIT"
    deployed=$(az containerapp show -g "$RESOURCE_GROUP" -n "$app" --query properties.template.containers[0].image -o tsv)
    [ "$deployed" = "$image" ] || { echo 'Digest implantado difere do aprovado'; exit 1; }
    export DEPLOY_APP="$app" DEPLOY_URL="https://$url" DEPLOY_IMAGE="$image"
    node --input-type=module -e 'import fs from "node:fs";fs.writeFileSync(".release/"+process.argv[1]+".json",JSON.stringify({build:process.env.BUILD_NUMBER,commit:process.env.RELEASE_COMMIT,commit_at:process.env.COMMIT_AT,deployed_at:new Date().toISOString(),app:process.env.DEPLOY_APP,url:process.env.DEPLOY_URL,image:process.env.DEPLOY_IMAGE,approved_by:process.env.APPROVED_BY||null,approved_at:process.env.APPROVED_AT||null},null,2));' "$action"
    ;;
  *) echo 'Ação inválida'; exit 1 ;;
esac
