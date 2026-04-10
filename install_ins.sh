#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[1/7] 安装基础软件..."
apt update
apt install -y sudo curl wget unzip git vim jq cron

echo "[2/7] 执行系统优化脚本..."
bash <(curl -Ls https://raw.githubusercontent.com/DDAICHICAO/rule_list/main/tools/sys.sh)

echo "[3/7] 安装 Nyanpass 节点 1..."
S=nyanpass-1 bash <(curl -fLSs https://dl.nyafw.com/download/nyanpass-install.sh) rel_nodeclient "-t 60a31c9c-0958-45cf-8dd7-4c070ae1601e -u https://ny.as9929.uk

echo "[5/7] 写入 Cloudflare DDNS 配置..."
mkdir -p /etc/cf-ddns

cat > /etc/cf-ddns/cf-ddns.conf <<'EOF'
# Cloudflare API Token
CF_API_TOKEN="cfat_EOBsaw2AberWvBHSJOJGXtTyOVDmSkp1uJHITdXj1f30b071"

# Cloudflare Zone ID
CF_ZONE_ID="这里改成你的Zone_ID"

# IPv4 和 IPv6 分别绑定的域名
CF_RECORD_NAME_V4="aws-ddns-v4-2601.nod3.org"
CF_RECORD_NAME_V6="aws-ddns-v6-2601.nod3.org"

# 是否启用 IPv4 / IPv6
ENABLE_IPV4="true"
ENABLE_IPV6="true"

# 是否走 Cloudflare 代理（true=橙云，false=仅DNS）
PROXIED="false"

# TTL
TTL="120"
EOF

echo "[6/7] 写入 DDNS 更新脚本..."
cat > /usr/local/bin/cf-ddns.sh <<'EOF'
#!/bin/bash
set -euo pipefail

CONFIG_FILE="/etc/cf-ddns/cf-ddns.conf"
[ -f "$CONFIG_FILE" ] || { echo "配置文件不存在: $CONFIG_FILE"; exit 1; }
# shellcheck disable=SC1090
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

  if [ -n "$data" ]; then
    curl -fsS -X "$method" "$url" \
      -H "$AUTH_HEADER" \
      -H "$CONTENT_HEADER" \
      --data "$data"
  else
    curl -fsS -X "$method" "$url" \
      -H "$AUTH_HEADER" \
      -H "$CONTENT_HEADER"
  fi
}

ensure_record() {
  local type="$1"
  local name="$2"
  local ip="$3"

  [ -n "$name" ] || {
    log "$type 域名未配置，跳过"
    return 0
  }

  [ -n "$ip" ] || {
    log "$type 未获取到公网IP，跳过"
    return 0
  }

  local list_url="${CF_API}/zones/${CF_ZONE_ID}/dns_records?type=${type}&name=${name}"
  local list_resp
  list_resp="$(cf_request GET "$list_url")"

  local success
  success="$(echo "$list_resp" | jq -r '.success')"
  [ "$success" = "true" ] || {
    log "查询 $type 记录失败: $list_resp"
    return 1
  }

  local record_id current_ip
  record_id="$(echo "$list_resp" | jq -r '.result[0].id // empty')"
  current_ip="$(echo "$list_resp" | jq -r '.result[0].content // empty')"

  if [ -n "$record_id" ]; then
    if [ "$current_ip" = "$ip" ]; then
      log "$type ${name} 无变化: $ip"
      return 0
    fi

    local update_data
    update_data="$(jq -n \
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

    local update_url="${CF_API}/zones/${CF_ZONE_ID}/dns_records/${record_id}"
    local update_resp
    update_resp="$(cf_request PATCH "$update_url" "$update_data")"

    if [ "$(echo "$update_resp" | jq -r '.success')" = "true" ]; then
      log "$type 已更新: ${name} -> $ip"
    else
      log "$type 更新失败: $update_resp"
      return 1
    fi
  else
    local create_data
    create_data="$(jq -n \
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

    local create_url="${CF_API}/zones/${CF_ZONE_ID}/dns_records"
    local create_resp
    create_resp="$(cf_request POST "$create_url" "$create_data")"

    if [ "$(echo "$create_resp" | jq -r '.success')" = "true" ]; then
      log "$type 已创建: ${name} -> $ip"
    else
      log "$type 创建失败: $create_resp"
      return 1
    fi
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

echo "[7/7] 配置定时任务并首次执行..."
cat > /etc/cron.d/cf-ddns <<'EOF'
*/5 * * * * root /usr/local/bin/cf-ddns.sh >> /var/log/cf-ddns.log 2>&1
EOF

systemctl enable cron
systemctl restart cron || service cron restart

/usr/local/bin/cf-ddns.sh || true

echo
echo "=========================================="
echo "安装完成"
echo "=========================================="
echo "配置文件: /etc/cf-ddns/cf-ddns.conf"
echo "DDNS脚本: /usr/local/bin/cf-ddns.sh"
echo "日志文件: /var/log/cf-ddns.log"
echo
echo "请先编辑配置文件："
echo "vim /etc/cf-ddns/cf-ddns.conf"
echo
echo "至少修改这两个值："
echo "CF_API_TOKEN"
echo "CF_ZONE_ID"
echo
echo "修改后可手动执行测试："
echo "/usr/local/bin/cf-ddns.sh"
echo
echo "查看日志："
echo "tail -f /var/log/cf-ddns.log"
