#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

usage() {
  cat <<'EOF'
用法:
  bash query.sh [选项]

选项:
  --nyanpass-uuid UUID         Nyanpass UUID，可重复传入
  --nyanpass-uuids UUIDS       多个 Nyanpass UUID，逗号/空格分隔
  --nyanpass-url URL           Nyanpass 服务地址，默认 https://ny.as9929.uk
  --nyanpass-urls URLS         多个 Nyanpass 服务地址，逗号/空格分隔
  --nyanpass-name NAME         Nyanpass 服务名，可重复传入
  --nyanpass-names NAMES       多个 Nyanpass 服务名，逗号/空格分隔
  --help                       显示帮助

也支持环境变量:
  NYANPASS_UUID / NYANPASS_UUIDS
  NYANPASS_URL / NYANPASS_URLS
  NYANPASS_NAME / NYANPASS_NAMES

示例:
  NYANPASS_UUIDS='uuid1,uuid2,uuid3' \
  NYANPASS_NAMES='nyanpass-1,nyanpass-2,nyanpass-3' \
  bash query.sh
EOF
}

NYANPASS_UUID_DEFAULT=""
NYANPASS_URL_DEFAULT="https://ny.as9929.uk"

NYANPASS_UUID_INPUTS=()
NYANPASS_URL_INPUTS=()
NYANPASS_NAME_INPUTS=()
NYANPASS_UUID_LIST=()
NYANPASS_URL_LIST=()
NYANPASS_NAME_LIST=()
NYANPASS_SERVICE_NAMES=()
NYANPASS_SERVICE_URLS=()
NYANPASS_UUID_CLI_SET="false"
NYANPASS_URL_CLI_SET="false"
NYANPASS_NAME_CLI_SET="false"

require_value() {
  local option="$1"
  local value="${2:-}"

  if [ -z "$value" ]; then
    echo "缺少参数值: ${option}"
    exit 1
  fi
}

append_values() {
  local -n target="$1"
  local raw="$2"
  local item

  raw="${raw//$'\r'/ }"
  raw="${raw//$'\n'/ }"
  raw="${raw//,/ }"

  for item in $raw; do
    [ -n "$item" ] && target+=("$item")
  done
}

load_env_nyanpass_inputs() {
  local uuid_source="${NYANPASS_UUIDS:-${NYANPASS_UUID:-$NYANPASS_UUID_DEFAULT}}"
  local url_source="${NYANPASS_URLS:-${NYANPASS_URL:-$NYANPASS_URL_DEFAULT}}"
  local name_source="${NYANPASS_NAMES:-${NYANPASS_NAME:-}}"

  if [ -n "$uuid_source" ]; then
    NYANPASS_UUID_INPUTS+=("$uuid_source")
  fi
  if [ -n "$url_source" ]; then
    NYANPASS_URL_INPUTS+=("$url_source")
  fi
  if [ -n "$name_source" ]; then
    NYANPASS_NAME_INPUTS+=("$name_source")
  fi
}

validate_service_name() {
  local name="$1"

  if ! [[ "$name" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
    echo "Nyanpass 服务名只能包含字母、数字、点、下划线、@ 和横线: ${name}"
    exit 1
  fi
}

build_nyanpass_install_plan() {
  local count="${#NYANPASS_UUID_LIST[@]}"
  local url_count="${#NYANPASS_URL_LIST[@]}"
  local name_count="${#NYANPASS_NAME_LIST[@]}"
  local i service_name service_url existing_name

  if [ "$url_count" -eq 0 ]; then
    NYANPASS_URL_LIST=("$NYANPASS_URL_DEFAULT")
    url_count=1
  fi

  if [ "$url_count" -ne 1 ] && [ "$url_count" -ne "$count" ]; then
    echo "NYANPASS_URLS 数量必须是 1 个，或与 NYANPASS_UUIDS 数量一致。"
    echo "当前 UUID 数量: ${count}, URL 数量: ${url_count}"
    exit 1
  fi

  if [ "$name_count" -ne 0 ] && [ "$name_count" -ne "$count" ]; then
    echo "NYANPASS_NAMES 数量必须与 NYANPASS_UUIDS 数量一致。"
    echo "当前 UUID 数量: ${count}, 名称数量: ${name_count}"
    exit 1
  fi

  for i in "${!NYANPASS_UUID_LIST[@]}"; do
    if [ "$name_count" -eq 0 ]; then
      service_name="nyanpass-$((i + 1))"
    else
      service_name="${NYANPASS_NAME_LIST[$i]}"
    fi

    service_url="${NYANPASS_URL_LIST[0]}"
    if [ "$url_count" -eq "$count" ]; then
      service_url="${NYANPASS_URL_LIST[$i]}"
    fi

    validate_service_name "$service_name"

    for existing_name in "${NYANPASS_SERVICE_NAMES[@]}"; do
      if [ "$existing_name" = "$service_name" ]; then
        echo "Nyanpass 服务名不能重复: ${service_name}"
        exit 1
      fi
    done

    NYANPASS_SERVICE_NAMES+=("$service_name")
    NYANPASS_SERVICE_URLS+=("$service_url")
  done
}

load_env_nyanpass_inputs

while [ $# -gt 0 ]; do
  case "$1" in
    --nyanpass-uuid|--nyanpass-uuids)
      require_value "$1" "${2:-}"
      if [ "$NYANPASS_UUID_CLI_SET" = "false" ]; then
        NYANPASS_UUID_INPUTS=()
        NYANPASS_UUID_CLI_SET="true"
      fi
      NYANPASS_UUID_INPUTS+=("$2")
      shift 2
      ;;
    --nyanpass-url|--nyanpass-urls)
      require_value "$1" "${2:-}"
      if [ "$NYANPASS_URL_CLI_SET" = "false" ]; then
        NYANPASS_URL_INPUTS=()
        NYANPASS_URL_CLI_SET="true"
      fi
      NYANPASS_URL_INPUTS+=("$2")
      shift 2
      ;;
    --nyanpass-name|--nyanpass-names|--nyanpass-service-name|--nyanpass-service-names)
      require_value "$1" "${2:-}"
      if [ "$NYANPASS_NAME_CLI_SET" = "false" ]; then
        NYANPASS_NAME_INPUTS=()
        NYANPASS_NAME_CLI_SET="true"
      fi
      NYANPASS_NAME_INPUTS+=("$2")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1"
      echo
      usage
      exit 1
      ;;
  esac
done

for raw_input in "${NYANPASS_UUID_INPUTS[@]}"; do
  append_values NYANPASS_UUID_LIST "$raw_input"
done

for raw_input in "${NYANPASS_URL_INPUTS[@]}"; do
  append_values NYANPASS_URL_LIST "$raw_input"
done

for raw_input in "${NYANPASS_NAME_INPUTS[@]}"; do
  append_values NYANPASS_NAME_LIST "$raw_input"
done

if [ "${#NYANPASS_UUID_LIST[@]}" -eq 0 ]; then
  read -r -p "请输入 Nyanpass UUID（多个用逗号或空格分隔）: " NYANPASS_UUID_INPUT
  append_values NYANPASS_UUID_LIST "$NYANPASS_UUID_INPUT"
fi

if [ "${#NYANPASS_UUID_LIST[@]}" -eq 0 ]; then
  echo "Nyanpass UUID 不能为空"
  exit 1
fi

build_nyanpass_install_plan

echo "[1/3] 安装基础软件..."
apt update
apt install -y sudo curl wget unzip git vim ca-certificates

echo "[2/3] 执行系统优化脚本..."
bash <(curl -Ls https://static.37ccys.uk/rule/sys.sh)

echo "[3/3] 安装 Nyanpass 节点客户端 (${#NYANPASS_UUID_LIST[@]} 个)..."
for i in "${!NYANPASS_UUID_LIST[@]}"; do
  echo "  - ${NYANPASS_SERVICE_NAMES[$i]} -> ${NYANPASS_SERVICE_URLS[$i]}"
  S="${NYANPASS_SERVICE_NAMES[$i]}" bash <(curl -fLSs https://dl.nyafw.com/download/nyanpass-install.sh) rel_nodeclient "-t ${NYANPASS_UUID_LIST[$i]} -u ${NYANPASS_SERVICE_URLS[$i]}"
done

echo
echo "=========================================="
echo "Nyanpass 安装完成"
echo "=========================================="
echo "Nyanpass 客户端:"
for i in "${!NYANPASS_UUID_LIST[@]}"; do
  echo "  - ${NYANPASS_SERVICE_NAMES[$i]}: ${NYANPASS_SERVICE_URLS[$i]}"
done
