# 🧱 Port Filter Script - Enhanced Version

改进版端口访问控制脚本，新增IP白名单、规则库选择等核心功能。

## ✨ 新增功能

### 🎯 IP白名单功能
- ✅ 支持单个IP地址（如：192.168.1.100）
- ✅ 支持IP段（如：10.0.0.0/8）
- ✅ 白名单IP优先于所有过滤规则
- ✅ 动态添加/删除白名单IP

### 🛠 规则库管理
- ✅ 可选择使用1-2个规则库（避免误拦截）
- ✅ 内置5个规则库，可根据需要选择
- ✅ 动态激活/停用规则库
- ✅ 配置自动保存

### 📋 内置规则库

| 规则库名称 | 描述 | 端口列表 |
|-----------|------|----------|
| `common_attacks` | 常见攻击端口 | 22, 23, 135, 139, 445, 1433, 3389 |
| `malware_ports` | 已知恶意软件端口 | 135, 4444, 5554, 8866, 9996, 12345, 27374 |
| `scan_detection` | 扫描检测端口 | 1, 7, 9, 11, 15, 21, 25, 111, 135, 139, 445 |
| `web_services` | Web服务端口 | 80, 443, 8080, 8888 |
| `database_ports` | 数据库端口 | 3306, 5432, 1433, 1521, 27017 |

## 🚀 快速安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/install-enhanced.sh)
```

## 📦 功能菜单

### 主菜单
| 序号 | 功能 | 说明 |
| ---- | ---- | ---- |
| 1 | IP白名单管理 | 添加/删除白名单IP |
| 2 | 规则库管理 | 选择激活的规则库 |
| 3 | 查看当前规则 | 显示iptables规则 |
| 4 | 清除所有规则 | 移除所有配置 |
| 5 | 保存并退出 | 保存配置并退出 |

### IP白名单管理
- **添加IP**: 输入单个IP或IP段
- **删除IP**: 从白名单移除IP
- **优先级**: 白名单IP不会被任何规则拦截

### 规则库管理
- **选择规则**: 输入规则库名称（空格分隔）
- **建议**: 同时激活不超过2个规则库，避免误拦截
- **示例**: `common_attacks malware_ports`

## 💻 命令行使用

### 添加白名单IP
```bash
sudo port-filter-enhanced --whitelist 192.168.1.100
sudo port-filter-enhanced --whitelist 10.0.0.0/8
```

### 设置规则库
```bash
sudo port-filter-enhanced --rules "common_attacks"
sudo port-filter-enhanced --rules "common_attacks malware_ports"
```

### 启动交互式菜单
```bash
sudo port-filter-enhanced
```

## 📋 使用示例

### 场景1：保护服务器，但允许内网访问
```bash
# 添加内网IP段到白名单
sudo port-filter-enhanced --whitelist 192.168.0.0/16

# 激活常见攻击端口过滤
sudo port-filter-enhanced --rules "common_attacks"
```

### 场景2：严格过滤，只允许特定IP
```bash
# 添加特定IP到白名单
sudo port-filter-enhanced --whitelist 203.0.113.100
sudo port-filter-enhanced --whitelist 203.0.113.200

# 激活多个规则库
sudo port-filter-enhanced --rules "common_attacks malware_ports"
```

### 场景3：Web服务器保护
```bash
# 添加管理IP到白名单
sudo port-filter-enhanced --whitelist 192.168.1.100

# 只激活Web服务相关的规则
sudo port-filter-enhanced --rules "web_services"
```

## 🔧 技术特点

- **基于iptables/ipset**: 高性能，内核级过滤
- **白名单优先**: 白名单IP不会被任何规则拦截
- **动态配置**: 无需重启服务，配置即时生效
- **自动保存**: 配置更改自动持久化
- **错误处理**: 完善的错误检查和提示

## 🗂 配置文件

- **主配置**: `/etc/port-filter/settings.conf`
- **白名单**: `/etc/port-filter/whitelist.conf`
- **规则文件**: `/etc/port-filter/rules.conf`

## 🧹 卸载

```bash
sudo rm -f /usr/local/bin/port-filter-enhanced
sudo iptables -F INPUT
sudo ipset destroy whitelist 2>/dev/null
sudo rm -rf /etc/port-filter
```

## ⚠️ 注意事项

1. **白名单优先**: 添加到白名单的IP不会被任何规则拦截
2. **规则选择**: 建议同时激活的规则库不超过2个，避免误拦截
3. **IP格式**: 支持单个IP（192.168.1.100）和IP段（10.0.0.0/8）
4. **权限要求**: 需要root权限运行
5. **备份建议**: 修改配置前建议备份重要数据

## 🐛 故障排除

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

**注意**: 这是原始项目的增强版本，专注于解决误拦截问题和提供更灵活的规则管理功能。