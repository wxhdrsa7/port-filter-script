# 🧱 Port Filter Script - Enhanced Version

一键配置服务器端口访问规则，支持国内/国际分流、端口屏蔽放行、IP白名单管理、规则库选择等功能。

## ✨ 新增功能

### 🎯 IP白名单管理
- ✅ 支持单个IP地址和IP段
- ✅ 白名单IP不会被任何规则拦截
- ✅ 动态添加/删除白名单IP
- ✅ 命令行快速添加

### 🛠 规则库选择
- ✅ 可选择激活1-2个规则库（避免误拦截）
- ✅ 内置5个规则库，按需选择
- ✅ 动态切换规则库

### 📋 内置规则库

| 规则库名称 | 描述 | 端口列表 |
|-----------|------|----------|
| `common_attacks` | 常见攻击端口 | 22, 23, 135, 139, 445, 1433, 3389 |
| `malware_ports` | 已知恶意软件端口 | 135, 4444, 5554, 8866, 9996, 12345, 27374 |
| `scan_detection` | 扫描检测端口 | 1, 7, 9, 11, 15, 21, 25, 111, 135, 139, 445 |
| `web_services` | Web服务端口 | 80, 443, 8080, 8888 |
| `database_ports` | 数据库端口 | 3306, 5432, 1433, 1521, 27017 |

## ✨ 原有功能
- ✅ 国内/国际 IP 地域过滤（黑名单、白名单）
- ✅ 一键屏蔽或放行指定端口（支持 TCP / UDP / 双协议）
- ✅ 多源中国 IP 列表聚合导入，规则更全面
- ✅ 支持计划任务，自动定时更新 IP 数据
- ✅ 彩色交互菜单，SSH 终端友好
- ✅ iptables/ipset 规则持久化保存

## 📦 菜单功能概览

### 主菜单
| 序号 | 功能 | 说明 |
| ---- | ---- | ---- |
| 1 | IP 地域过滤 | 选择端口、协议，设置黑名单（阻止国内）或白名单（只允许国内） |
| 2 | 屏蔽端口 | 完全阻断指定端口访问 |
| 3 | 放行端口 | 完全放通指定端口 |
| 4 | 查看 iptables 规则 | 快速检查当前防火墙规则（前 20 条） |
| 5 | IP 白名单管理 | 添加/删除IP白名单，白名单IP不会被拦截 |
| 6 | 规则库选择 | 选择要激活的规则库（建议不超过2个） |
| 7 | 清除所有规则 | 移除所有本脚本添加的规则、计划任务与配置 |
| 8 | 立即更新中国 IP | 手动刷新多源中国 IP 列表 |
| 9 | 配置自动更新 | 设置每天的自动更新时间（24 小时制） |
| 10 | 查看已保存的策略 | 以表格形式查看通过脚本设置的端口策略和白名单 |
| 11 | 退出 | 保存配置并退出程序 |

### IP白名单管理
- **添加白名单**: 输入单个IP（192.168.1.100）或IP段（10.0.0.0/8）
- **优先级**: 白名单IP不会被任何过滤规则拦截
- **动态生效**: 添加后立即生效，无需重启

### 规则库选择
- **灵活选择**: 可选择1-2个规则库同时激活
- **避免误拦截**: 建议根据实际需求选择，不要全部激活
- **动态切换**: 可随时更换激活的规则库

## 🚀 安装

### 一键安装（推荐）
```bash
bash <(curl -sL https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/install.sh)
```

### 手动安装
```bash
curl -sL https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/port-filter.sh -o /usr/local/bin/port-filter
chmod +x /usr/local/bin/port-filter
sudo port-filter
```

## 💻 使用方法

### 启动交互式菜单
```bash
sudo port-filter
```

### 命令行快速添加白名单
```bash
# 添加单个IP
sudo port-filter --whitelist 192.168.1.100

# 添加IP段
sudo port-filter --whitelist 10.0.0.0/8
```

## 📋 使用示例

### 场景1：保护服务器，但允许内网访问
```bash
# 添加内网IP段到白名单
sudo port-filter --whitelist 192.168.0.0/16

# 启动菜单，选择规则库
sudo port-filter
# 选择菜单6，激活 common_attacks 规则库
```

### 场景2：严格过滤，只允许特定IP
```bash
# 添加管理IP到白名单
sudo port-filter --whitelist 203.0.113.100
sudo port-filter --whitelist 203.0.113.200

# 启动菜单，选择多个规则库
sudo port-filter
# 选择菜单6，激活 common_attacks 和 malware_ports
```

### 场景3：Web服务器保护
```bash
# 添加CDN和管理IP到白名单
sudo port-filter --whitelist 192.168.1.100

# 启动菜单，选择web服务规则
sudo port-filter
# 选择菜单6，激活 web_services 规则库
```

## ⚠️ 注意事项

1. **白名单优先**: 添加到白名单的IP不会被任何规则拦截
2. **规则选择**: 建议同时激活的规则库不超过2个，避免误拦截
3. **IP格式**: 支持单个IP（192.168.1.100）和IP段（10.0.0.0/8）
4. **权限要求**: 需要root权限运行
5. **备份建议**: 修改配置前建议备份重要数据

## 🧹 卸载

```bash
sudo rm -f /usr/local/bin/port-filter
sudo iptables -F INPUT
sudo ipset destroy china 2>/dev/null
sudo ipset destroy whitelist 2>/dev/null
sudo rm -rf /etc/port-filter
```

## 🔧 故障排除

### 规则不生效
- 检查是否使用了root权限
- 确认iptables服务正在运行
- 查看是否有其他防火墙规则冲突

### 白名单无效
- 检查IP格式是否正确
- 确认IP是否已添加到白名单文件
- 查看iptables规则顺序

### 误拦截问题
- 减少同时激活的规则库数量
- 添加必要IP到白名单
- 检查规则库端口列表

---

**新增功能**: IP白名单管理、规则库选择、命令行快速配置
**优化改进**: 减少误拦截、提高灵活性、简化操作流程