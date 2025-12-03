# Linux端口过滤系统 v3.0

## 简介

Linux端口过滤系统是一个功能强大的网络安全工具，集成了端口过滤、IP白名单管理、数据源管理和系统监控功能。

## 核心特性

- ✅ **IP白名单（最高优先级）** - 确保关键IP不会被误拦截
- ✅ **端口过滤** - 基于协议和端口的访问控制
- ✅ **数据源管理** - 动态IP数据源的启用和管理
- ✅ **系统监控** - 实时状态监控和日志记录
- ✅ **备份恢复** - 配置和数据的备份与恢复

## 快速开始

### 1. 安装依赖
```bash
# Ubuntu/Debian
apt-get install iptables ipset curl wget jq

# CentOS/RHEL
yum install iptables ipset curl wget jq
```

### 2. 下载并安装
```bash
# 下载主脚本
wget -O /usr/local/bin/port-filter https://your-domain.com/port-filter-master.sh
chmod +x /usr/local/bin/port-filter

# 创建符号链接
ln -sf /usr/local/bin/port-filter /usr/local/bin/pf
```

### 3. 快速配置
```bash
# 启动快速向导
port-filter wizard

# 或直接配置
port-filter whitelist-add 192.168.1.100    # 添加白名单IP
port-filter apply 22 tcp                   # 过滤SSH端口
port-filter apply 80 tcp                   # 过滤HTTP端口
```

## 使用示例

### 白名单管理（最高优先级）
```bash
port-filter whitelist-add 192.168.1.100           # 添加单个IP
port-filter whitelist-add 10.0.0.0/8              # 添加CIDR段
port-filter whitelist-add 2001:db8::/32           # 添加IPv6段
port-filter whitelist-show                        # 显示白名单
port-filter whitelist-remove 192.168.1.100        # 移除IP
```

### 端口过滤
```bash
port-filter apply 22 tcp                          # 过滤SSH
port-filter apply 80 tcp                          # 过滤HTTP
port-filter apply 443 tcp                         # 过滤HTTPS
port-filter remove 22 tcp                         # 移除过滤
```

### 系统管理
```bash
port-filter status                                # 查看状态
port-filter backup                                # 创建备份
port-filter cleanup                               # 清理规则
port-filter                                       # 交互式菜单
```

## 文件说明

### 核心文件
- `port-filter-master.sh` - 主脚本（完整功能）
- `COMPLETE_DOCUMENTATION.md` - 完整文档
- `INSTALLATION_GUIDE.md` - 安装指南

### 测试文件
- `test-all-functions.sh` - 功能测试
- `whitelist-priority-demo.sh` - 白名单优先级演示

### 信息文件
- `DEPLOYMENT_INFO.md` - 部署信息
- `README.md` - 本文件

## 白名单优先级说明

本系统的IP白名单具有**最高优先级**，优先级顺序如下：

1. **白名单IP** → 直接接受连接（最高优先级）
2. **过滤规则** → 按规则处理（中等优先级）
3. **默认策略** → 按系统默认处理（最低优先级）

这意味着：
- 白名单中的IP可以访问任何端口
- 白名单优先级高于数据源过滤规则
- 白名单优先级高于端口过滤规则

## 系统要求

- Linux操作系统（推荐Ubuntu/CentOS）
- root权限
- 网络连接
- 50MB磁盘空间

## 技术支持

- 完整文档：`COMPLETE_DOCUMENTATION.md`
- 安装指南：`INSTALLATION_GUIDE.md`
- 功能测试：`test-all-functions.sh`
- 演示脚本：`whitelist-priority-demo.sh`

---

**版本**: 3.0  
**发布日期**: 2025-12-03  
**维护者**: 系统管理员