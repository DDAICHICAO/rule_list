#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

usage() {
  cat <<'EOF'
用法:
  bash install_ins.sh [选项]

选项:
  --nyanpass-uuid UUID         Nyanpass UUID
  --cf-api-token TOKEN         Cloudflare API Token
  --cf-zone-id ZONE_ID         Cloudflare Zone ID
  --cf-record-v4 DOMAIN        IPv4 绑定域名
  --cf-record-v6 DOMAIN        IPv6 绑定域名
  --cf-proxied true|false      Cloudflare 代理开关，默认 false
  --cf-ttl TTL                 DNS TTL，默认 120
  --help                       显示帮助

也支持环境变量:
  NYANPASS_UUID
  CF_API_TOKEN
  CF_ZONE_ID
  CF_RECORD_NAME_V4
  CF_RECORD_NAME_V6
  CF_PROXIED
  CF_TTL

示例:
  CF_API_TOKEN='xxxx' \
  bash install_ins.sh \
    --nyanpass-uuid 60a31c9c-0958-45cf-8dd7-4c070ae1601e \
    --cf-zone-id 0be2c57373680f2880a9d674809b996b \
    --cf-record-v4 aws-ddns-v4-2601.nod3.org \
    --cf-record-v6 aws-ddns-v6-2601.nod3.org
EOF
}

NYANPASS_UUID_DEFAULT=""
CF_ZONE_ID_DEFAULT="0be2c57373680f2880a9d674809b996b"
CF_RECORD_NAME_V4_DEFAULT="aws-ddns-v4-2601.nod3.org"
CF_RECORD_NAME_V6_DEFAULT="aws-ddns-v6-2601.nod3.org"
CF_PROXIED_DEFAULT="false"
CF_TTL_DEFAULT="120"

NYANPASS_UUID="${NYANPASS_UUID:-$NYANPASS_UUID_DEFAULT}"
CF_API_TOKEN="${CF_API_TOKEN:-}"
CF_ZONE_ID="${CF_ZONE_ID:-$CF_ZONE_ID_DEFAULT}"
CF_RECORD_NAME_V4="${CF_RECORD_NAME_V4:-$CF_RECORD_NAME_V4_DEFAULT}"
CF_RECORD_NAME_V6="${CF_RECORD_NAME_V6:-$CF_RECORD_NAME_V6_DEFAULT}"
CF_PROXIED="${CF_PROXIED:-$CF_PROXIED_DEFAULT}"
CF_TTL="${CF_TTL:-$CF_TTL_DEFAULT}"

while [ $# -gt 0 ]; do
  case "$1" in
    --nyanpass-uuid)
      NYANPASS_UUID="$2"
      shift 2
      ;;
    --cf-api-token)
      CF_API_TOKEN="$2"
      shift 2
      ;;
    --cf-zone-id)
      CF_ZONE_ID="$2"
      shift 2
      ;;
    --cf-record-v4)
      CF_RECORD_NAME_V4="$2"
      shift 2
      ;;
    --cf-record-v6)
      CF_RECORD_NAME_V6="$2"
      shift 2
      ;;
    --cf-proxied)
      CF_PROXIED="$2"
      shift 2
      ;;
    --cf-ttl)
      CF_TTL="$2"
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

if [ -z "$NYANPASS_UUID" ]; then
  read -r -p "请输入 Nyanpass UUID: " NYANPASS_UUID
fi

if [ -z "$CF_API_TOKEN" ]; then
  read -r -s -p "请输入 Cloudflare API Token: " CF_API_TOKEN
  echo
fi

echo "[1/8] 安装基础软件..."
apt update
apt install -y sudo curl wget unzip git vim jq cron

echo "[2/8] 执行系统优化脚本..."
bash <(curl -Ls https://raw.githubusercontent.com/DDAICHICAO/rule_list/main/tools/sys.sh)

echo "[3/8] 安装 Nyanpass 节点客户端..."
S=nyanpass-1 bash <(curl -fLSs https://dl.nyafw.com/download/nyanpass-install.sh) rel_nodeclient "-t ${NYANPASS_UUID} -u https://ny.as9929.uk"

echo "[4/8] 写入 Cloudflare 配置..."
mkdir -p /etc/cf-ddns

cat > /etc/cf-ddns/cf-ddns.conf <<EOF
CF_API_TOKEN="${CF_API_TOKEN}"
CF_ZONE_ID="${CF_ZONE_ID}"
CF_RECORD_NAME_V4="${CF_RECORD_NAME_V4}"
CF_RECORD_NAME_V6="${CF_RECORD_NAME_V6}"
ENABLE_IPV4="true"
ENABLE_IPV6="true"
PROXIED="${CF_PROXIED}"
TTL="${CF_TTL}"
EOF

chmod 600 /etc/cf-ddns/cf-ddns.conf

echo "[5/8] 写入 DDNS 更新脚本..."
cat > /usr/local/bin/cf-ddns.sh <<'EOF'
#!/bin/bash
set -euo pipefail

CONFIG_FILE="/etc/cf-ddns/cf-ddns.conf"
[ -f "$CONFIG_FILE" ] || { echo "配置文件不存在: $CONFIG_FILE"; exit 1; }
source "$CONFIG_FILE"

CF_API="https://api.cloudflare.com/client/v4"
AUTH_HEADER="Authorization: Bearer ${CF_API_TOKEN}"
CONTENT_HEADER="Content-Type: application/json"

log() {
  echo "[$(date '+%F %T')] $*"
}

get_ipv4() {
  curl -4 -fsS --max-time 10 https://api64.ipify.org || true
}

get_ipv6() {
  curl -6 -fsS --max-time 10 https://api64.ipify.org || true
}

cf_request() {
  local method="$1"
  local url="$2"
  local data="${3:-}"
  local resp http_code body

  if [ -n "$data" ]; then
    resp="$(curl -sS -w '\n%{http_code}' -X "$method" "$url" \
      -H "$AUTH_HEADER" \
      -H "$CONTENT_HEADER" \
      --data "$data")"
  else
    resp="$(curl -sS -w '\n%{http_code}' -X "$method" "$url" \
      -H "$AUTH_HEADER" \
      -H "$CONTENT_HEADER")"
  fi

  http_code="$(printf '%s\n' "$resp" | tail -n1)"
  body="$(printf '%s\n' "$resp" | sed '$d')"

  if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
    echo "HTTP $http_code: $body" >&2
    return 1
  fi

  printf '%s\n' "$body"
}

ensure_record() {
  local type="$1"
  local name="$2"
  local ip="$3"

  [ -n "$name" ] || { log "$type 域名未配置，跳过"; return 0; }
  [ -n "$ip" ] || { log "$type 未获取到公网IP，跳过"; return 0; }

  local list_resp
  list_resp="$(cf_request GET "${CF_API}/zones/${CF_ZONE_ID}/dns_records?type=${type}&name=${name}")"

  [ "$(echo "$list_resp" | jq -r '.success')" = "true" ] || {
    log "查询 $type 记录失败: $list_resp"
    return 1
  }

  local record_id current_ip
  record_id="$(echo "$list_resp" | jq -r '.result[0].id // empty')"
  current_ip="$(echo "$list_resp" | jq -r '.result[0].content // empty')"

  local payload
  payload="$(jq -n \
    --arg type "$type" \
    --arg name "$name" \
    --arg content "$ip" \
    --argjson proxied "${PROXIED}" \
    --argjson ttl "${TTL}" \
    '{
      type: $type,
      name: $name,
      content: $content,
      proxied: $proxied,
      ttl: $ttl
    }')"

  if [ -n "$record_id" ]; then
    if [ "$current_ip" = "$ip" ]; then
      log "$type ${name} 无变化: $ip"
      return 0
    fi

    local update_resp
    update_resp="$(cf_request PATCH "${CF_API}/zones/${CF_ZONE_ID}/dns_records/${record_id}" "$payload")"
    [ "$(echo "$update_resp" | jq -r '.success')" = "true" ] || {
      log "$type 更新失败: $update_resp"
      return 1
    }
    log "$type 已更新: ${name} -> $ip"
  else
    local create_resp
    create_resp="$(cf_request POST "${CF_API}/zones/${CF_ZONE_ID}/dns_records" "$payload")"
    [ "$(echo "$create_resp" | jq -r '.success')" = "true" ] || {
      log "$type 创建失败: $create_resp"
      return 1
    }
    log "$type 已创建: ${name} -> $ip"
  fi
}

main() {
  [ -n "${CF_API_TOKEN:-}" ] || { log "CF_API_TOKEN 未配置"; exit 1; }
  [ -n "${CF_ZONE_ID:-}" ] || { log "CF_ZONE_ID 未配置"; exit 1; }

  if [ "${ENABLE_IPV4}" = "true" ]; then
    IPV4="$(get_ipv4)"
    ensure_record "A" "${CF_RECORD_NAME_V4:-}" "$IPV4"
  fi

  if [ "${ENABLE_IPV6}" = "true" ]; then
    IPV6="$(get_ipv6)"
    ensure_record "AAAA" "${CF_RECORD_NAME_V6:-}" "$IPV6"
  fi
}

main "$@"
EOF

chmod +x /usr/local/bin/cf-ddns.sh

echo "[6/8] 配置 cron..."
cat > /etc/cron.d/cf-ddns <<'EOF'
* * * * * root /usr/local/bin/cf-ddns.sh >> /var/log/cf-ddns.log 2>&1
EOF

echo "[7/8] 启用 cron..."
systemctl enable cron
systemctl restart cron || service cron restart

echo "[8/8] 首次执行 DDNS..."
/usr/local/bin/cf-ddns.sh

echo
echo "=========================================="
echo "安装完成"
echo "=========================================="
echo "配置文件: /etc/cf-ddns/cf-ddns.conf"
echo "DDNS脚本: /usr/local/bin/cf-ddns.sh"
echo "日志文件: /var/log/cf-ddns.log"
echo
echo "手动执行： /usr/local/bin/cf-ddns.sh"
echo "查看日志： tail -f /var/log/cf-ddns.log"
