#!/bin/bash

# 更新系统并安装常用软件包
apt update && \
apt install -y sudo curl wget unzip git vim

# 执行系统优化脚本
bash <(curl -Ls https://raw.githubusercontent.com/DDAICHICAO/rule_list/main/tools/sys.sh)

# 安装 Nyanpass 节点客户端
S=nyanpass-1 bash <(curl -fLSs https://dl.nyafw.com/download/nyanpass-install.sh) rel_nodeclient "-o -t d8d427ee-e3f6-4863-8dc0-5d26ab11b216 -u https://ny.as9929.uk"

S=nyanpass-2 bash <(curl -fLSs https://dl.nyafw.com/download/nyanpass-install.sh) rel_nodeclient "-o -t 115f0244-2377-48d5-86a8-57a77e8916c9 -u https://mypass.v2link.top"
