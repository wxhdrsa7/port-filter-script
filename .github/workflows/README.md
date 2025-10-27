# 🛡️ 端口访问控制脚本

一键设置防火墙端口过滤规则，支持 IP 地域过滤、端口屏蔽/放行。

## ✨ 功能特性

- ✅ **IP 地域过滤**：黑名单/白名单模式，精准控制中国IP访问
- ✅ **端口管理**：一键屏蔽/放行指定端口
- ✅ **协议支持**：支持 TCP、UDP 或同时设置
- ✅ **自动更新**：定时更新中国IP列表，保持规则最新
- ✅ **交互式菜单**：简单易用的彩色菜单界面
- ✅ **规则持久化**：重启后自动恢复配置

## 🚀 快速安装

### 一键安装（推荐）
```bash
sudo bash <(curl -sL https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/install.sh)
```

或使用 wget：
```bash
sudo bash <(wget -qO- https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/install.sh)
```

### 使用 CDN（国内访问更快）
```bash
sudo bash <(curl -sL https://cdn.jsdelivr.net/gh/wxhdrsa7/port-filter-script/install.sh)
```

## 📖 使用方法

安装后运行以下任一命令：
```bash
pf              # 最短命令
port-filter     # 短命令
port_filter.sh  # 完整命令
```

## 🎯 使用场景

### 场景1：Shadowsocks 黑名单
阻止中国IP访问，允许其他国家连接
```
选择: 1 (IP地域过滤)
端口: 8388
协议: 3 (TCP + UDP)
模式: 1 (黑名单)
```

### 场景2：SSH 白名单
仅允许中国IP访问SSH
```
选择: 1 (IP地域过滤)
端口: 22
协议: 1 (TCP)
模式: 2 (白名单)
```

### 场景3：屏蔽危险端口
完全禁止某些端口访问
```
选择: 2 (屏蔽端口)
端口: 3389
协议: 1 (TCP)
```

## 📋 系统要求

- **操作系统**：Ubuntu 18.04+ / Debian 9+ / CentOS 7+
- **权限**：需要 root 权限
- **依赖**：自动安装 ipset、iptables-persistent、curl

## 🔧 主要功能

### 1. IP 地域过滤
- **黑名单模式**：阻止指定地区IP，允许其他地区
- **白名单模式**：仅允许指定地区IP，阻止其他地区
- 支持多端口、多协议配置

### 2. 端口控制
- **屏蔽端口**：完全阻止端口访问
- **放行端口**：完全允许端口访问
- 支持端口范围和批量操作

### 3. 自动更新
- 支持设置定时任务（每周自动更新）
- 多源下载备份（GitHub/jsDelivr/GitMirror）
- 本地缓存机制，网络故障时使用缓存

### 4. 规则管理
- 查看当前所有规则
- 一键清除所有规则
- 规则持久化保存

## 📸 截图
```
╔════════════════════════════════════════════════╗
║      端口访问控制脚本 v1.1.0                    ║
╚════════════════════════════════════════════════╝

1. IP地域过滤（黑名单/白名单）
2. 屏蔽端口（完全阻止访问）
3. 放行端口（完全允许访问）
4. 查看当前规则
5. 清除所有规则
6. 手动更新中国IP列表
7. 设置自动更新
8. 移除自动更新
0. 退出

请选择操作 [0-8]:
```

## ⚠️ 注意事项

1. **备份规则**：修改前建议先查看当前规则
2. **SSH 安全**：设置白名单前确保自己IP在允许范围内
3. **测试环境**：建议先在测试服务器验证规则
4. **定期更新**：建议启用自动更新功能

## 🔄 更新脚本

重新运行安装命令即可更新到最新版本：
```bash
sudo bash <(curl -sL https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/install.sh)
```

## 🐛 常见问题

### 1. 下载IP列表时卡住？
- 脚本会自动尝试多个下载源
- 支持本地缓存，网络失败时自动使用缓存
- 可以手动下载IP列表并放到 `/etc/port-filter/china_ip.txt`

### 2. 规则不生效？
```bash
# 查看当前规则
iptables -L INPUT -n -v

# 检查 ipset
ipset list china

# 查看日志
cat /etc/port-filter/update.log
```

### 3. 如何卸载？
```bash
# 运行脚本，选择 5 清除所有规则
pf

# 删除程序文件
sudo rm -f /usr/local/bin/port_filter.sh
sudo rm -f /usr/local/bin/pf
sudo rm -f /usr/local/bin/port-filter
sudo rm -rf /etc/port-filter
```

## 📄 开源协议

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📞 支持

如有问题请提交 [Issue](https://github.com/wxhdrsa7/port-filter-script/issues)
```

---

## 📂 最终文件结构

你的仓库应该有这些文件：
```
port-filter-script/
├── README.md           # 说明文档
├── port_filter.sh      # 主脚本
└── install.sh          # 安装脚本
```

---

## 🔗 你的专属链接

### 仓库地址
```
https://github.com/wxhdrsa7/port-filter-script
