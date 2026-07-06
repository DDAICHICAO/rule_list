#!/bin/bash

# 2024-07-29 23:16

# 确保脚本以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# 向 sysctl 配置文件中添加配置
tee -a /etc/sysctl.d/100-sysctl.conf > /dev/null <<EOL
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_fin_timeout=15
vm.max_map_count=262144
net.ipv4.tcp_slow_start_after_idle=0
net.core.netdev_budget=600
net.ipv4.tcp_notsent_lowat=2048
net.ipv4.tcp_max_syn_backlog=262144
net.ipv4.tcp_max_tw_buckets=262144
net.ipv4.ip_local_port_range=10000 60000
net.ipv4.tcp_mem=3145728 3932160 4718592
net.ipv4.tcp_syn_retries=3
net.ipv4.tcp_synack_retries=3
net.ipv4.tcp_retries1=3
net.ipv4.tcp_retries2=3
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_probes=6
net.ipv4.tcp_keepalive_intvl=60
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_fastopen=0
net.core.netdev_max_backlog=16384
net.core.default_qdisc=fq_pie
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_wmem=8192  1048576 33554432
net.ipv4.tcp_rmem=4096 131072 33554432
EOL

# 应用新的 sysctl 配置
sysctl -p /etc/sysctl.d/100-sysctl.conf

echo "Sysctl configuration has been updated and loaded."