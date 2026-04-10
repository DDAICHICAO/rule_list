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
