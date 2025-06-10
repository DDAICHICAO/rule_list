#!/bin/bash

# 检查是否为 root 用户或具有 sudo 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "此脚本需要 root 权限。请使用 sudo 运行此脚本。"
  exit 1
fi

echo "---"
echo "正在更新系统软件包列表..."
sudo apt update || { echo "软件包列表更新失败。请检查您的网络连接或软件源配置。"; exit 1; }

echo "---"
echo "正在安装必要的软件包..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common || { echo "必要软件包安装失败。"; exit 1; }

echo "---"
echo "正在添加 Docker 的官方 GPG 密钥..."
# 检查并安装 gnupg，以防 curl 命令失败
if ! command -v gpg &> /dev/null; then
    echo "gnupg 未安装，正在尝试安装..."
    sudo apt install -y gnupg || { echo "gnupg 安装失败。"; exit 1; }
fi
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || { echo "Docker GPG 密钥添加失败。"; exit 1; }

echo "---"
echo "正在添加 Docker 的稳定存储库..."
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || { echo "Docker 存储库添加失败。"; exit 1; }

echo "---"
echo "正在更新软件包列表以使存储库更改生效..."
sudo apt update || { echo "软件包列表更新失败。请检查您的网络连接或软件源配置。"; exit 1; }

echo "---"
echo "正在安装 Docker 引擎、CLI 和 containerd.io..."
sudo apt install -y docker-ce docker-ce-cli containerd.io || { echo "Docker 引擎安装失败。"; exit 1; }

echo "---"
echo "Docker 安装完成。正在检查 Docker 服务状态..."
sudo systemctl status docker

echo "---"
echo "您现在可以将当前用户添加到 docker 组，以便无需 sudo 即可运行 Docker 命令："
echo "sudo usermod -aG docker \$USER"
echo "然后注销并重新登录以使更改生效。"