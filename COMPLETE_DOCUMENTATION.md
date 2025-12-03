# Linux端口过滤系统完整文档

## 目录
1. [系统概述](#系统概述)
2. [功能特性](#功能特性)
3. [安装指南](#安装指南)
4. [配置说明](#配置说明)
5. [使用指南](#使用指南)
6. [IP白名单管理](#ip白名单管理)
7. [数据源管理](#数据源管理)
8. [系统管理](#系统管理)
9. [故障排除](#故障排除)
10. [最佳实践](#最佳实践)
11. [安全建议](#安全建议)
12. [性能优化](#性能优化)

## 系统概述

Linux端口过滤系统是一个功能强大的网络安全工具，集成了端口过滤、IP白名单管理、数据源库管理和系统监控功能。系统的核心设计理念是提供简单而有效的网络访问控制，同时确保白名单IP具有最高访问优先级。

### 核心组件
- **主脚本**: `port-filter-master.sh` - 集成所有功能的统一脚本
- **配置文件**: `/etc/port-filter/` - 系统配置目录
- **数据文件**: `/var/lib/port-filter/` - IP数据源和临时文件
- **日志文件**: `/var/log/port-filter/` - 操作日志和系统日志
- **备份文件**: `/var/backups/port-filter/` - 配置备份

## 功能特性

### 主要功能
1. **端口过滤** - 基于协议和端口的访问控制
2. **IP白名单** - 具有最高优先级的IP访问控制
3. **数据源管理** - 动态IP数据源的启用/禁用和管理
4. **系统监控** - 实时状态监控和日志记录
5. **备份恢复** - 配置和数据的备份与恢复
6. **快速向导** - 简化的配置流程

### 技术特性
- **IPv4/IPv6双栈支持** - 同时支持IPv4和IPv6
- **高效IP存储** - 使用IPSet进行高效的IP地址管理
- **优先级机制** - 白名单 > 过滤规则 > 默认规则
- **动态更新** - 支持数据源的自动更新
- **并发安全** - 文件锁定机制防止并发执行
- **完整日志** - 详细的操作日志记录

## 安装指南

### 系统要求
- Linux操作系统（推荐Ubuntu/CentOS）
- root权限
- 网络连接（用于下载IP数据）
- 至少50MB磁盘空间

### 依赖安装
```bash
# Ubuntu/Debian
apt-get update
apt-get install -y iptables ipset curl wget jq awk grep sed

# CentOS/RHEL
yum install -y iptables ipset curl wget jq awk grep sed
```

### 脚本安装
```bash
# 下载脚本
wget -O /usr/local/bin/port-filter-master.sh https://your-domain.com/port-filter-master.sh

# 设置权限
chmod +x /usr/local/bin/port-filter-master.sh

# 创建符号链接
ln -sf /usr/local/bin/port-filter-master.sh /usr/local/bin/port-filter
```

### 首次运行
```bash
# 以root权限运行
sudo port-filter

# 系统会自动初始化并显示主菜单
```

## 配置说明

### 配置文件结构
```
/etc/port-filter/
├── config.conf          # 主配置文件
├── whitelist.conf       # 白名单配置
├── datasources.conf     # 数据源配置
└── rules/              # 规则文件目录
```

### 主配置文件 (config.conf)
```ini
# 启用IPv6支持
IPV6_ENABLED=true

# 自动更新间隔（小时）
AUTO_UPDATE_INTERVAL=24

# 日志级别：DEBUG, INFO, WARN, ERROR
LOG_LEVEL=INFO

# 备份保留天数
BACKUP_RETENTION_DAYS=30

# 最大规则数限制
MAX_RULES=50000

# 数据源超时时间（秒）
DATASOURCE_TIMEOUT=30
```

### 数据源配置 (datasources.conf)
```
# 格式：name|url|enabled|description
china|https://iplist.cc/code/cn|true|中国IP段
usa|https://iplist.cc/code/us|false|美国IP段
russia|https://iplist.cc/code/ru|false|俄罗斯IP段
```

## 使用指南

### 命令行模式
```bash
# 应用端口过滤
port-filter apply 80 tcp
port-filter apply 443 tcp

# 移除端口过滤
port-filter remove 80 tcp

# 白名单管理
port-filter whitelist-add 192.168.1.100
port-filter whitelist-remove 192.168.1.100
port-filter whitelist-show

# 系统管理
port-filter status
port-filter backup
port-filter cleanup
```

### 交互式菜单
运行不带参数的脚本进入交互式菜单：
```bash
port-filter
```

菜单选项：
1. **应用端口过滤** - 为指定端口添加过滤规则
2. **移除端口过滤** - 移除指定端口的过滤规则
3. **IP白名单管理** - 管理白名单IP地址
4. **数据源管理** - 管理IP数据源
5. **系统状态** - 显示系统当前状态
6. **备份管理** - 创建和恢复备份
7. **清理所有规则** - 清除所有防火墙规则
8. **快速向导** - 简化配置流程

### 快速向导
快速向导提供简化的配置流程：

1. **配置IP白名单** - 添加需要绕过过滤的IP地址
2. **选择数据源** - 选择要使用的IP数据源
3. **配置端口过滤** - 设置需要过滤的端口和协议

## IP白名单管理

### 白名单优先级
IP白名单具有**最高优先级**，会覆盖所有其他过滤规则：
1. 白名单IP → 直接接受连接
2. 过滤规则 → 根据规则处理
3. 默认规则 → 按默认策略处理

### 支持的格式
- **单个IPv4地址**: `192.168.1.100`
- **单个IPv6地址**: `2001:db8::1`
- **IPv4 CIDR段**: `192.168.1.0/24`
- **IPv6 CIDR段**: `2001:db8::/32`

### 管理操作
```bash
# 添加IP到白名单
port-filter whitelist-add 192.168.1.100
port-filter whitelist-add 10.0.0.0/8
port-filter whitelist-add 2001:db8::/32

# 移除白名单IP
port-filter whitelist-remove 192.168.1.100

# 显示当前白名单
port-filter whitelist-show
```

### 白名单验证
系统自动验证IP地址格式：
- IPv4: 四段数字，每段0-255
- IPv6: 标准IPv6格式
- CIDR: 正确的子网掩码范围

## 数据源管理

### 内置数据源
系统提供以下内置数据源：
- **china**: 中国IP地址段
- **usa**: 美国IP地址段
- **russia**: 俄罗斯IP地址段
- **iran**: 伊朗IP地址段
- **northkorea**: 朝鲜IP地址段

### 自定义数据源
可以添加自定义数据源：
```
# 格式：name|url|enabled|description
mycompany|https://example.com/ips.txt|true|公司IP段
```

### 数据源操作
1. **启用/禁用数据源** - 控制数据源是否生效
2. **添加自定义数据源** - 添加新的数据源
3. **更新数据源** - 从远程更新IP数据
4. **查看状态** - 显示数据源状态

## 系统管理

### 状态监控
```bash
port-filter status
```

显示内容包括：
- 系统版本和路径信息
- IPSet集合状态
- 防火墙规则状态
- 数据源状态

### 备份恢复
```bash
# 创建备份
port-filter backup

# 备份文件位置
/var/backups/port-filter/backup_YYYYMMDD_HHMMSS.tar.gz
```

### 日志管理
日志文件位置：`/var/log/port-filter/port-filter.log`

日志级别：
- **DEBUG**: 调试信息
- **INFO**: 一般信息
- **WARN**: 警告信息
- **ERROR**: 错误信息

### 系统清理
```bash
# 清理所有规则
port-filter cleanup

# 清理旧备份
find /var/backups/port-filter -name "*.tar.gz" -mtime +30 -delete
```

## 故障排除

### 常见问题

#### 1. 脚本无法运行
**问题**: 权限错误
**解决**: 确保以root权限运行
```bash
sudo port-filter
```

#### 2. 白名单不生效
**问题**: IP格式错误或规则未加载
**解决**: 
- 检查IP格式是否正确
- 重新加载白名单
```bash
port-filter whitelist-show
```

#### 3. 数据源更新失败
**问题**: 网络连接或URL错误
**解决**:
- 检查网络连接
- 验证URL有效性
- 检查防火墙设置

#### 4. 端口过滤无效
**问题**: 规则冲突或优先级问题
**解决**:
- 检查现有iptables规则
- 确认白名单IP是否正确
- 查看系统日志

### 调试模式
```bash
# 修改配置文件
sed -i 's/LOG_LEVEL=INFO/LOG_LEVEL=DEBUG/' /etc/port-filter/config.conf

# 重新运行
port-filter
```

### 日志分析
```bash
# 查看实时日志
tail -f /var/log/port-filter/port-filter.log

# 搜索错误日志
grep ERROR /var/log/port-filter/port-filter.log

# 查看特定时间日志
sed -n '/2025-12-03 10:00:00/,/2025-12-03 11:00:00/p' /var/log/port-filter/port-filter.log
```

## 最佳实践

### 1. 初始配置
1. **先配置白名单** - 确保管理IP不会被误拦截
2. **选择合适的数据源** - 根据实际需求选择数据源
3. **测试配置** - 在生产环境前充分测试

### 2. 白名单管理
1. **添加管理IP** - 首先添加管理员IP到白名单
2. **使用CIDR段** - 对整个内网网段使用CIDR格式
3. **定期维护** - 定期检查和更新白名单

### 3. 数据源选择
1. **按需选择** - 只选择需要的数据源
2. **定期更新** - 定期更新数据源IP信息
3. **验证数据** - 确保数据源URL有效

### 4. 系统维护
1. **定期备份** - 定期创建系统备份
2. **监控日志** - 定期检查系统日志
3. **清理旧文件** - 定期清理过期备份和日志

## 安全建议

### 1. 访问控制
- **限制脚本访问** - 只允许授权用户执行脚本
- **保护配置文件** - 设置正确的文件权限
- **监控使用情况** - 记录所有操作日志

### 2. 网络安全
- **使用HTTPS** - 数据源URL使用HTTPS协议
- **验证数据源** - 确保数据源来自可信来源
- **定期更新** - 及时更新系统和依赖

### 3. 系统安全
- **最小权限** - 使用最小必要权限运行
- **定期审计** - 定期审计系统配置
- **备份策略** - 建立完善的备份策略

## 性能优化

### 1. IPSet优化
- **合理设置maxelem** - 根据预期IP数量设置
- **使用合适的hash类型** - 选择适合的hash算法
- **定期清理** - 清理过期和无效的IP

### 2. 规则优化
- **减少规则数量** - 合并相似的规则
- **优化规则顺序** - 将常用规则放在前面
- **使用集合** - 使用IPSet代替大量单IP规则

### 3. 系统优化
- **调整日志级别** - 生产环境使用INFO级别
- **定期维护** - 定期重启和清理
- **监控资源** - 监控系统资源使用情况

## 示例配置

### 基础配置示例
```bash
# 添加内网IP到白名单
port-filter whitelist-add 192.168.0.0/16
port-filter whitelist-add 10.0.0.0/8
port-filter whitelist-add 172.16.0.0/12

# 过滤常用端口
port-filter apply 22 tcp    # SSH
port-filter apply 80 tcp    # HTTP
port-filter apply 443 tcp   # HTTPS
```

### 高级配置示例
```bash
# 添加自定义数据源
echo "company|https://company.com/ips.txt|true|公司IP段" >> /etc/port-filter/datasources.conf

# 启用数据源
# 在数据源管理菜单中启用

# 应用复杂过滤规则
port-filter apply 3306 tcp  # MySQL
port-filter apply 6379 tcp  # Redis
port-filter apply 27017 tcp # MongoDB
```

## 技术支持

### 获取帮助
- 查看系统日志：`tail -f /var/log/port-filter/port-filter.log`
- 检查系统状态：`port-filter status`
- 查看白名单：`port-filter whitelist-show`

### 报告问题
报告问题时请提供：
- 系统版本和发行版信息
- 错误日志（如果有）
- 配置文件内容（脱敏后）
- 复现步骤

### 更新和维护
- 定期检查脚本更新
- 关注依赖包的安全更新
- 维护数据源的有效性

---

**文档版本**: 3.0  
**最后更新**: 2025-12-03  
**维护者**: 系统管理员