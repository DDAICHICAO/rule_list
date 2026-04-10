#!/bin/bash
set -e

# 更新系统并安装常用软件包
apt update && \
apt install -y sudo curl wget unzip git vim

# 执行系统优化脚本
bash <(curl -Ls https://raw.githubusercontent.com/DDAICHICAO/rule_list/main/tools/sys.sh)

# 安装 Nyanpass 节点客户端
S=nyanpass-1 bash <(curl -fLSs https://dl.nyafw.com/download/nyanpass-install.sh) rel_nodeclient "-o -t d8d427ee-e3f6-4863-8dc0-5d26ab11b216 -u https://ny.as9929.uk"

# Cloudflare DDNS
CF_TOKEN="cfat_aKGtMrq0RcNSnPkS0TJNZs4nPWCh925vV0eMfs43d17e3423"
CF_ZONE_ID="0be2c57373680f2880a9d674809b996b"

# IPv4 -> aws-ddns-v4-2601.nod3.org
bash <(curl -Ls https://git.io/cloudflare-ddns) -k "$CF_TOKEN" \
  -h aws-ddns-v4-2601.nod3.org \
  -z "$CF_ZONE_ID" \
  -t A

# IPv6 -> aws-ddns-v6-2601.nod3.org
bash <(curl -Ls https://git.io/cloudflare-ddns) -k "$CF_TOKEN" \
  -h aws-ddns-v6-2601.nod3.org \
  -z "$CF_ZONE_ID" \
  -t AAAA
