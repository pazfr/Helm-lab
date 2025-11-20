#!/usr/bin/env bash
set -euo pipefail

# Generates Helm values files from Kustomize bases/overlays under ./apps.
# Requires yq v4 (already available in this repo environment).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR="${ROOT_DIR}/apps"
VALUES_DIR="${ROOT_DIR}/helm/values/services"

mkdir -p "${VALUES_DIR}"

log() { echo "[$(date +'%H:%M:%S')]" "$@"; }

render_base_values() {
  local svc="$1"
  local svc_dir="${APPS_DIR}/${svc}"
  local base="${svc_dir}/base"

  local deployment="${base}/deployment.yaml"
  local service="${base}/service.yaml"
  local ingress="${base}/ingress.yaml"
  local scaledobject="${base}/scaledobject-keda.yaml"
  local secret="${base}/secret.yaml"

  if [ ! -f "${deployment}" ] || [ ! -f "${service}" ]; then
    log "  Skipping ${svc} (missing deployment/service in base)"
    return
  fi

  local image repo tag primary_port target_port ports ingress_internal ingress_class ingress_annotations extra_env shared_env force_shared

  repo="$(yq '.spec.template.spec.containers[0].image' "${deployment}" | cut -d':' -f1)"
  tag="$(yq '.spec.template.spec.containers[0].image' "${deployment}" | cut -d':' -f2-)"
  primary_port="$(yq '.spec.ports[0].port' "${service}")"
  target_port="$(yq '.spec.ports[0].targetPort // .spec.ports[0].port' "${service}")"
  ports="$(yq '[.spec.ports[] | {"name": .name // "", "port": .port, "targetPort": (.targetPort // .port), "protocol": (.protocol // "TCP")}]' "${service}")"
  ingress_class="$(yq '.spec.ingressClassName // "alb"' "${ingress}")"
  ingress_annotations="$(yq '.metadata.annotations' "${ingress}" 2>/dev/null || echo '{}')"
  ingress_internal="$(yq '.metadata.annotations["alb.ingress.kubernetes.io/scheme"] == "internal"' "${ingress}")"
  if [ -f "${secret}" ]; then
    secret_name="$(yq '.metadata.name' "${secret}")"
  else
    secret_name="${svc}-secrets"
  fi
  resources="$(yq '.spec.template.spec.containers[0].resources' "${deployment}")"

  # Detect envFrom shared-configmap usage to plumb extraEnv.
  extra_env_list="$(yq '[.spec.template.spec.containers[0].env[] | select(.valueFrom.configMapKeyRef.name == "shared-configmap")]' "${deployment}" 2>/dev/null || echo '[]')"

  cat > "${VALUES_DIR}/${svc}.yaml" <<EOF
replicaCount: $(yq '.spec.replicas // 1' "${deployment}")
service:
  name: ${svc}
  port: ${primary_port}
  targetPort: ${target_port}
  ports:
$(echo "${ports}" | yq 'to_yaml' | sed 's/^/  /')

ingress:
  internal: ${ingress_internal}
  className: ${ingress_class}
  annotations:
$(echo "${ingress_annotations}" | yq 'to_yaml' | sed 's/^/    /')
  paths:
$(yq '[.spec.rules[0].http.paths[] | {"path": .path, "pathType": .pathType, "serviceName": .backend.service.name, "port": .backend.service.port.number}]' "${ingress}" | yq 'to_yaml' | sed 's/^/    /')

image:
  repository: ${repo}
  tag: ${tag}

resources:
$(echo "${resources}" | yq 'to_yaml' | sed 's/^/  /')

config:
  create: true
  name: ${svc}-config
  data: {}

secret:
  create: false
  name: ${secret_name}

externalSecrets: []
EOF

  # Add any shared-configmap env refs.
  if [ "$(echo "${extra_env_list}" | yq 'length')" != "0" ]; then
    {
      echo
      echo "extraEnv:"
      echo "${extra_env_list}" | yq 'to_yaml' | sed 's/^/  /'
    } >> "${VALUES_DIR}/${svc}.yaml"
  fi

  # Add scaledObject if present.
  if [ -f "${scaledobject}" ]; then
    local polling cooldown minRep maxRep triggers
    cat >> "${VALUES_DIR}/${svc}.yaml" <<EOF

scaledObject:
  enabled: true
$(yq '{"pollingInterval": .spec.pollingInterval, "cooldownPeriod": .spec.cooldownPeriod, "minReplicaCount": .spec.minReplicaCount, "maxReplicaCount": .spec.maxReplicaCount, "triggers": .spec.triggers}' "${scaledobject}" | sed 's/^/  /')
EOF
  fi
}

render_env_values() {
  local svc="$1"
  local env_dir="$2"
  local env_name
  env_name="$(basename "${env_dir}")"
  local outfile="${VALUES_DIR}/${svc}-${env_name}.yaml"

  local kustom="${env_dir}/kustomization.yaml"
  local ingress_patch="${env_dir}/ingress-patch.yaml"
  local external_secret_patch="${env_dir}/external-secret-patch.yaml"

  # Image tag
  local image_tag
  image_tag="$(yq '.images[0].newTag // ""' "${kustom}")"

  # ConfigMap literals
  local config_data
  config_data="$(yq '.configMapGenerator[0].literals // []' "${kustom}" 2>/dev/null)" || config_data="[]"
  config_yaml="{}"
  if [ "$(printf '%s\n' "${config_data}" | yq 'length')" != "0" ]; then
    config_yaml=$(printf '%s\n' "${config_data}" | yq '.[]' | while IFS= read -r line; do
      key="${line%%=*}"
      val="${line#*=}"
      printf '%s: "%s"\n' "${key}" "${val}"
    done)
  fi

  # Service label version
  local version_label
  version_label="$(yq '.commonLabels.version // ""' "${kustom}")"

  # Ingress annotations
  local ingress_annotations="{}"
  if [ -f "${ingress_patch}" ]; then
    ingress_annotations="$(yq '.metadata.annotations // {}' "${ingress_patch}")"
  fi

  cat > "${outfile}" <<EOF
image:
  tag: ${image_tag}

service:
  labels:
    version: "${version_label}"

config:
  data:
$(if [ "${config_yaml}" != "{}" ]; then printf '%s\n' "${config_yaml}" | sed 's/^/    /'; else echo "    {}"; fi)

ingress:
  annotations:
$(echo "${ingress_annotations}" | yq 'to_yaml' | sed 's/^/    /')
EOF

  # ExternalSecrets per environment
  if [ -f "${external_secret_patch}" ]; then
    echo >> "${outfile}"
    echo "externalSecrets:" >> "${outfile}"
    yq eval-all '. as $item ireduce([]; . + [$item])' "${external_secret_patch}" | \
      yq eval '[.[] | {"name": .metadata.name, "secretStoreRef": .spec.secretStoreRef, "refreshInterval": .spec.refreshInterval, "targetName": .spec.target.name, "data": .spec.data}]' - | \
      yq eval 'to_yaml' - | sed 's/^/  /' >> "${outfile}"
  fi
}

main() {
  for svc in $(ls "${APPS_DIR}" | grep -v '^shared-infra$'); do
    if [ ! -d "${APPS_DIR}/${svc}/base" ]; then
      continue
    fi
    log "Generating base values for ${svc}"
    render_base_values "${svc}"
    for env_dir in "${APPS_DIR}/${svc}/overlays"/*; do
      [ -d "${env_dir}" ] || continue
      if [ ! -f "${env_dir}/kustomization.yaml" ]; then
        log "  Skipping env $(basename "${env_dir}") for ${svc} (no kustomization.yaml)"
        continue
      fi
      log "  Generating env $(basename "${env_dir}") for ${svc}"
      render_env_values "${svc}" "${env_dir}"
    done
  done
  log "Done. Review files under ${VALUES_DIR}"
}

main "$@"
