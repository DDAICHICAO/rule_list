#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

usage() {
  cat <<'EOF'
用法:
  bash ddns.sh [选项]

选项:
  --cf-api-token TOKEN         Cloudflare API Token
  --cf-zone-id ZONE_ID         Cloudflare Zone ID（兼容保留，ddns-go 会按域名查询 zone）
  --cf-record-v4 DOMAIN        IPv4 绑定域名，多个用逗号/空格分隔
  --cf-record-v6 DOMAIN        IPv6 绑定域名，多个用逗号/空格分隔
  --cf-enable-v4 true|false|auto
  --cf-enable-v6 true|false|auto
  --cf-proxied true|false      Cloudflare 代理开关，默认 false
  --cf-ttl TTL                 DNS TTL，默认 120
  --ddns-go-version VERSION    ddns-go 版本，默认 latest
  --ddns-go-interval SECONDS   ddns-go 同步间隔，默认 600
  --ddns-go-cache-times N      ddns-go 服务商比对间隔次数，默认 3
  --ddns-go-web true|false     是否开启 ddns-go Web，默认 false
  --ddns-go-listen ADDRESS     Web 监听地址，默认 127.0.0.1:9876
  --help                       显示帮助

也支持环境变量:
  CF_API_TOKEN
  CF_ZONE_ID
  CF_RECORD_NAME_V4
  CF_RECORD_NAME_V6
  CF_ENABLE_IPV4
  CF_ENABLE_IPV6
  CF_PROXIED
  CF_TTL
  DDNS_GO_VERSION
  DDNS_GO_INTERVAL
  DDNS_GO_CACHE_TIMES
  DDNS_GO_WEB
  DDNS_GO_LISTEN

示例:
  CF_API_TOKEN='xxxx' \
  CF_RECORD_NAME_V4='node-1.example.com' \
  CF_RECORD_NAME_V6='' \
  CF_ENABLE_IPV6='false' \
  bash ddns.sh
EOF
}

CF_ZONE_ID_DEFAULT=""
CF_RECORD_NAME_V4_DEFAULT=""
CF_RECORD_NAME_V6_DEFAULT=""
CF_ENABLE_IPV4_DEFAULT="auto"
CF_ENABLE_IPV6_DEFAULT="auto"
CF_PROXIED_DEFAULT="false"
CF_TTL_DEFAULT="120"
DDNS_GO_VERSION_DEFAULT="latest"
DDNS_GO_CONFIG_DEFAULT="/etc/ddns-go/ddns_go_config.yaml"
DDNS_GO_BIN_DEFAULT="/usr/local/bin/ddns-go"
DDNS_GO_INTERVAL_DEFAULT="600"
DDNS_GO_CACHE_TIMES_DEFAULT="3"
DDNS_GO_WEB_DEFAULT="false"
DDNS_GO_LISTEN_DEFAULT="127.0.0.1:9876"

CF_API_TOKEN="${CF_API_TOKEN:-}"
CF_ZONE_ID="${CF_ZONE_ID:-$CF_ZONE_ID_DEFAULT}"
CF_RECORD_NAME_V4="${CF_RECORD_NAME_V4-$CF_RECORD_NAME_V4_DEFAULT}"
CF_RECORD_NAME_V6="${CF_RECORD_NAME_V6-$CF_RECORD_NAME_V6_DEFAULT}"
CF_ENABLE_IPV4="${CF_ENABLE_IPV4:-$CF_ENABLE_IPV4_DEFAULT}"
CF_ENABLE_IPV6="${CF_ENABLE_IPV6:-$CF_ENABLE_IPV6_DEFAULT}"
CF_PROXIED="${CF_PROXIED:-$CF_PROXIED_DEFAULT}"
CF_TTL="${CF_TTL:-$CF_TTL_DEFAULT}"
DDNS_GO_VERSION="${DDNS_GO_VERSION:-$DDNS_GO_VERSION_DEFAULT}"
DDNS_GO_CONFIG="${DDNS_GO_CONFIG:-$DDNS_GO_CONFIG_DEFAULT}"
DDNS_GO_BIN="${DDNS_GO_BIN:-$DDNS_GO_BIN_DEFAULT}"
DDNS_GO_INTERVAL="${DDNS_GO_INTERVAL:-$DDNS_GO_INTERVAL_DEFAULT}"
DDNS_GO_CACHE_TIMES="${DDNS_GO_CACHE_TIMES:-$DDNS_GO_CACHE_TIMES_DEFAULT}"
DDNS_GO_WEB="${DDNS_GO_WEB:-$DDNS_GO_WEB_DEFAULT}"
DDNS_GO_LISTEN="${DDNS_GO_LISTEN:-$DDNS_GO_LISTEN_DEFAULT}"

require_value() {
  local option="$1"
  local value="${2:-}"

  if [ -z "$value" ]; then
    echo "缺少参数值: ${option}"
    exit 1
  fi
}

validate_bool_or_auto() {
  local name="$1"
  local value="$2"

  case "$value" in
    true|false|auto)
      ;;
    *)
      echo "${name} 只能是 true、false 或 auto: ${value}"
      exit 1
      ;;
  esac
}

validate_bool() {
  local name="$1"
  local value="$2"

  case "$value" in
    true|false)
      ;;
    *)
      echo "${name} 只能是 true 或 false: ${value}"
      exit 1
      ;;
  esac
}

validate_positive_int() {
  local name="$1"
  local value="$2"

  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "${name} 必须是正整数: ${value}"
    exit 1
  fi
}

resolve_cf_enable() {
  local value="$1"
  local record_name="$2"

  case "$value" in
    true|false)
      printf '%s\n' "$value"
      ;;
    auto)
      if [ -n "$record_name" ]; then
        printf 'true\n'
      else
        printf 'false\n'
      fi
      ;;
  esac
}

write_yaml_domains() {
  local raw="$1"
  local indent="$2"
  local item count=0 suffix=""

  raw="${raw//$'\r'/ }"
  raw="${raw//$'\n'/ }"
  raw="${raw//,/ }"

  if [ -n "${CF_PROXIED:-}" ]; then
    suffix="?proxied=${CF_PROXIED}"
  fi

  for item in $raw; do
    if [ "$count" -eq 0 ]; then
      printf '%sdomains:\n' "$indent"
    fi
    printf '%s  - "%s%s"\n' "$indent" "$item" "$suffix"
    count=$((count + 1))
  done

  if [ "$count" -eq 0 ]; then
    printf '%sdomains: []\n' "$indent"
  fi
}

detect_ddns_go_asset() {
  local os arch

  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  if [ "$os" != "linux" ]; then
    echo "ddns-go 自动安装当前只支持 Linux，当前系统: ${os}" >&2
    exit 1
  fi

  case "$arch" in
    x86_64|amd64)
      printf 'linux_x86_64\n'
      ;;
    aarch64|arm64)
      printf 'linux_arm64\n'
      ;;
    armv7l|armv7*)
      printf 'linux_armv7\n'
      ;;
    armv6l|armv6*)
      printf 'linux_armv6\n'
      ;;
    armv5l|armv5*)
      printf 'linux_armv5\n'
      ;;
    riscv64)
      printf 'linux_riscv64\n'
      ;;
    *)
      echo "不支持的 ddns-go Linux 架构: ${arch}" >&2
      exit 1
      ;;
  esac
}

resolve_ddns_go_version() {
  local version="$1"

  if [ "$version" != "latest" ]; then
    printf '%s\n' "$version"
    return 0
  fi

  version="$(curl -fsSL https://api.github.com/repos/jeessy2/ddns-go/releases/latest \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' \
    | head -n1)"

  if [ -z "$version" ]; then
    echo "无法获取 ddns-go 最新版本号" >&2
    exit 1
  fi

  printf '%s\n' "$version"
}

install_ddns_go() {
  local version version_no_v asset archive url tmp_dir

  version="$(resolve_ddns_go_version "$DDNS_GO_VERSION")"
  version_no_v="${version#v}"
  asset="$(detect_ddns_go_asset)"
  archive="ddns-go_${version_no_v}_${asset}.tar.gz"
  url="https://github.com/jeessy2/ddns-go/releases/download/${version}/${archive}"
  tmp_dir="$(mktemp -d)"

  trap 'rm -rf "$tmp_dir"' RETURN

  curl -fL -o "${tmp_dir}/ddns-go.tar.gz" "$url"
  tar -xzf "${tmp_dir}/ddns-go.tar.gz" -C "$tmp_dir"
  install -m 0755 "${tmp_dir}/ddns-go" "$DDNS_GO_BIN"
}

write_ddns_go_config() {
  mkdir -p "$(dirname "$DDNS_GO_CONFIG")"

  {
    printf 'dnsconf:\n'
    printf '  - name: "cloudflare-ddns"\n'
    printf '    ipv4:\n'
    printf '      enable: %s\n' "$CF_ENABLE_IPV4_RESOLVED"
    printf '      gettype: url\n'
    printf '      url: "https://api.ipify.org, https://ddns.oray.com/checkip, https://ip.3322.net, https://4.ipw.cn"\n'
    printf '      netinterface: ""\n'
    printf '      cmd: ""\n'
    write_yaml_domains "$CF_RECORD_NAME_V4" "      "
    printf '    ipv6:\n'
    printf '      enable: %s\n' "$CF_ENABLE_IPV6_RESOLVED"
    printf '      gettype: url\n'
    printf '      url: "https://api64.ipify.org, https://v6.ident.me, https://6.ipw.cn"\n'
    printf '      netinterface: ""\n'
    printf '      cmd: ""\n'
    printf '      ipv6reg: ""\n'
    write_yaml_domains "$CF_RECORD_NAME_V6" "      "
    printf '    dns:\n'
    printf '      name: cloudflare\n'
    printf '      id: "%s"\n' "$CF_ZONE_ID"
    printf '      secret: "%s"\n' "$CF_API_TOKEN"
    printf '      extparam: ""\n'
    printf '    ttl: "%s"\n' "$CF_TTL"
    printf '    httpinterface: ""\n'
    printf 'notallowwanaccess: true\n'
    printf 'lang: zh-cn\n'
  } > "$DDNS_GO_CONFIG"

  chmod 600 "$DDNS_GO_CONFIG"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --cf-api-token)
      require_value "$1" "${2:-}"
      CF_API_TOKEN="$2"
      shift 2
      ;;
    --cf-zone-id)
      require_value "$1" "${2:-}"
      CF_ZONE_ID="$2"
      shift 2
      ;;
    --cf-record-v4)
      require_value "$1" "${2:-}"
      CF_RECORD_NAME_V4="$2"
      shift 2
      ;;
    --cf-record-v6)
      require_value "$1" "${2:-}"
      CF_RECORD_NAME_V6="$2"
      shift 2
      ;;
    --cf-enable-v4)
      require_value "$1" "${2:-}"
      CF_ENABLE_IPV4="$2"
      shift 2
      ;;
    --cf-enable-v6)
      require_value "$1" "${2:-}"
      CF_ENABLE_IPV6="$2"
      shift 2
      ;;
    --cf-proxied)
      require_value "$1" "${2:-}"
      CF_PROXIED="$2"
      shift 2
      ;;
    --cf-ttl)
      require_value "$1" "${2:-}"
      CF_TTL="$2"
      shift 2
      ;;
    --ddns-go-version)
      require_value "$1" "${2:-}"
      DDNS_GO_VERSION="$2"
      shift 2
      ;;
    --ddns-go-interval)
      require_value "$1" "${2:-}"
      DDNS_GO_INTERVAL="$2"
      shift 2
      ;;
    --ddns-go-cache-times)
      require_value "$1" "${2:-}"
      DDNS_GO_CACHE_TIMES="$2"
      shift 2
      ;;
    --ddns-go-web)
      require_value "$1" "${2:-}"
      DDNS_GO_WEB="$2"
      shift 2
      ;;
    --ddns-go-listen)
      require_value "$1" "${2:-}"
      DDNS_GO_LISTEN="$2"
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

validate_bool_or_auto "CF_ENABLE_IPV4" "$CF_ENABLE_IPV4"
validate_bool_or_auto "CF_ENABLE_IPV6" "$CF_ENABLE_IPV6"
validate_bool "CF_PROXIED" "$CF_PROXIED"
validate_bool "DDNS_GO_WEB" "$DDNS_GO_WEB"
validate_positive_int "DDNS_GO_INTERVAL" "$DDNS_GO_INTERVAL"
validate_positive_int "DDNS_GO_CACHE_TIMES" "$DDNS_GO_CACHE_TIMES"

CF_ENABLE_IPV4_RESOLVED="$(resolve_cf_enable "$CF_ENABLE_IPV4" "$CF_RECORD_NAME_V4")"
CF_ENABLE_IPV6_RESOLVED="$(resolve_cf_enable "$CF_ENABLE_IPV6" "$CF_RECORD_NAME_V6")"

if [ "$CF_ENABLE_IPV4_RESOLVED" != "true" ] && [ "$CF_ENABLE_IPV6_RESOLVED" != "true" ]; then
  echo "至少需要配置一个 DDNS 域名：CF_RECORD_NAME_V4 或 CF_RECORD_NAME_V6"
  exit 1
fi

if [ -z "$CF_API_TOKEN" ]; then
  read -r -s -p "请输入 Cloudflare API Token: " CF_API_TOKEN
  echo
fi

echo "[1/5] 安装基础软件..."
apt update
apt install -y curl ca-certificates tar

echo "[2/5] 写入 ddns-go 配置..."
write_ddns_go_config

echo "[3/5] 安装 ddns-go..."
install_ddns_go

echo "[4/5] 清理旧 cf-ddns cron..."
rm -f /etc/cron.d/cf-ddns
pkill -f '/usr/local/bin/cf-ddns.sh' 2>/dev/null || true
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart cron 2>/dev/null || true
else
  service cron restart 2>/dev/null || true
fi

echo "[5/5] 启用 ddns-go 服务..."
"$DDNS_GO_BIN" -s uninstall 2>/dev/null || true
DDNS_GO_INSTALL_ARGS=(-s install -f "$DDNS_GO_INTERVAL" -cacheTimes "$DDNS_GO_CACHE_TIMES" -c "$DDNS_GO_CONFIG")
if [ "$DDNS_GO_WEB" = "true" ]; then
  DDNS_GO_INSTALL_ARGS+=(-l "$DDNS_GO_LISTEN")
else
  DDNS_GO_INSTALL_ARGS+=(-noweb)
fi
"$DDNS_GO_BIN" "${DDNS_GO_INSTALL_ARGS[@]}"

echo
echo "=========================================="
echo "ddns-go 安装完成"
echo "=========================================="
echo "配置文件: ${DDNS_GO_CONFIG}"
echo "程序路径: ${DDNS_GO_BIN}"
echo "查看服务: systemctl status ddns-go"
echo "查看日志: journalctl -u ddns-go -f"
