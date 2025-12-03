# 端口过滤脚本改进版

## 简介

这是一个功能强大的服务器端口访问控制脚本，基于原始版本进行全面改进，提供更安全、更稳定、更丰富的功能。

## 主要特性

### 🛡️ 安全性增强
- **输入验证**: 严格的端口、协议、模式验证
- **并发保护**: 文件锁定机制防止重复执行
- **权限控制**: 安全的文件和目录权限设置
- **系统检查**: 自动检测系统兼容性

### 🔧 功能扩展
- **IPv6支持**: 完整的IPv4/IPv6双栈支持
- **系统监控**: 实时系统状态和性能监控
- **备份恢复**: 自动备份和手动恢复功能
- **增强日志**: 详细的操作日志和错误日志

### 📊 性能优化
- **多源IP**: 多个可靠的IP数据源
- **异步下载**: 并行下载提高更新效率
- **内存优化**: 合理的内存使用策略
- **规则优化**: 高效的iptables规则管理

### 🎨 用户体验
- **友好界面**: 彩色交互式菜单
- **操作确认**: 重要操作的二次确认
- **状态反馈**: 详细的操作结果反馈
- **帮助系统**: 完整的帮助和说明

## 安装使用

### 快速开始
```bash
# 下载脚本
wget https://github.com/wxhdrsa7/port-filter-script/raw/main/port-filter-improved.sh

# 设置执行权限
chmod +x port-filter-improved.sh

# 运行脚本
sudo ./port-filter-improved.sh
```

### 命令行参数
```bash
# 更新IP列表
sudo ./port-filter-improved.sh --update-ip

# 查看系统状态
sudo ./port-filter-improved.sh --status

# 创建备份
sudo ./port-filter-improved.sh --backup

# 查看版本
sudo ./port-filter-improved.sh --version

# 显示帮助
sudo ./port-filter-improved.sh --help
```

## 功能菜单

### 主菜单选项
1. **IP地域过滤** - 设置端口的地域访问控制
2. **屏蔽端口** - 完全阻止指定端口访问
3. **放行端口** - 完全允许指定端口访问
4. **查看规则** - 显示当前防火墙规则
5. **清除规则** - 删除所有脚本添加的规则
6. **更新IP列表** - 手动更新中国IP地址列表
7. **自动更新配置** - 设置定时自动更新
8. **查看策略** - 显示已保存的端口策略
9. **系统状态** - 查看系统运行状态
10. **备份恢复** - 管理配置备份
0. **退出** - 退出脚本

### 使用示例

#### 设置IP地域过滤
```bash
选择菜单: 1
输入端口号: 8080
选择协议: 3 (TCP+UDP)
选择模式: 2 (白名单-仅允许中国IP)
确认操作: y
```

#### 屏蔽危险端口
```bash
选择菜单: 2
输入端口号: 23 (Telnet)
选择协议: 3 (TCP+UDP)
确认操作: y
```

#### 配置自动更新
```bash
选择菜单: 7
输入时间: 03:30 (每天3:30更新)
确认操作: y
```

## 系统要求

### 操作系统
- Ubuntu 18.04 或更高版本
- Debian 9 或更高版本
- CentOS 7 或更高版本
- RedHat 7 或更高版本
- Fedora 28 或更高版本

### 依赖软件
- bash 4.0+
- iptables 1.4+
- ipset 6.0+
- curl 7.0+
- crontab

### 系统权限
- 必须以root权限运行
- 需要网络连接以下载IP列表
- 需要iptables和ipset的管理权限

## 配置文件

### 配置文件位置
- 主配置目录: `/etc/port-filter/`
- 规则文件: `/etc/port-filter/rules.conf`
- 设置文件: `/etc/port-filter/settings.conf`
- 备份目录: `/etc/port-filter/backups/`

### 日志文件
- 主日志: `/var/log/port-filter/update.log`
- 错误日志: `/var/log/port-filter/error.log`
- 测试日志: `/var/log/port-filter-test.log`

## 安全建议

### 定期维护
```bash
# 设置自动更新IP列表
# 每天凌晨3:30自动更新

# 定期创建备份
sudo ./port-filter-improved.sh --backup

# 监控日志文件
tail -f /var/log/port-filter/error.log
```

### 最佳实践
1. **最小权限原则**: 只开放必需的端口
2. **定期更新**: 保持IP列表的最新状态
3. **备份配置**: 重要配置变更前创建备份
4. **监控日志**: 定期检查错误和警告日志
5. **测试验证**: 生产环境使用前充分测试

## 故障排除

### 常见问题

#### IP列表下载失败
```bash
# 检查网络连接
ping -c 4 github.com

# 检查DNS设置
nslookup github.com

# 检查防火墙
iptables -L
```

#### 规则不生效
```bash
# 检查iptables服务
systemctl status iptables

# 验证规则存在
iptables -L INPUT -n

# 检查IPSet内容
ipset list china
```

#### 自动更新失败
```bash
# 检查crontab
crontab -l

# 查看cron日志
tail -f /var/log/cron

# 手动测试更新
sudo ./port-filter-improved.sh --update-ip
```

### 获取帮助

#### 查看日志
```bash
# 查看更新日志
tail -f /var/log/port-filter/update.log

# 查看错误日志
tail -f /var/log/port-filter/error.log

# 查看系统日志
journalctl -u cron
```

#### 测试功能
```bash
# 运行测试套件
sudo ./test-port-filter.sh

# 查看测试结果
cat /var/log/port-filter-test.log
```

## 版本历史

### v2.1.0 (当前版本)
- ✅ IPv6支持
- ✅ 系统状态监控
- ✅ 备份恢复功能
- ✅ 增强日志系统
- ✅ 性能优化
- ✅ 安全性增强

### v2.0.0 (原始版本)
- ✅ IP地域过滤
- ✅ 端口控制
- ✅ 自动更新
- ✅ 交互菜单

## 许可证

本项目基于原始项目改进，遵循相同的开源许可证。

## 贡献

欢迎提交Issue和Pull Request来改进这个项目。

## 联系方式

如有问题或建议，请通过以下方式联系：
- GitHub Issues
- 邮件反馈
- 技术社区讨论

---

**注意**: 使用本脚本前请确保了解iptables和网络安全基础知识，建议在测试环境验证后再部署到生产环境。