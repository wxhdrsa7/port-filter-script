# 🧱 Port Filter Script

一键设置防火墙端口过滤规则，支持 IP 地域过滤、端口屏蔽/放行。

## ✨ 功能特性
- ✅ IP 地域过滤（黑/白名单）
- ✅ 一键屏蔽/放行指定端口
- ✅ 支持 TCP / UDP / Both
- ✅ 自动更新中国 IP 列表
- ✅ 永久保存规则（iptables-persistent）
- ✅ 彩色交互菜单，SSH 兼容

## 🚀 一键安装命令
```bash
bash <(curl -sL https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/install.sh)
🔧 手动运行
sudo port-filter

🧹 卸载
sudo rm -f /usr/local/bin/port-filter
sudo iptables -F INPUT
sudo ipset destroy china 2>/dev/null
