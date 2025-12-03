# IP数据源库管理功能说明

## 功能概述

IP数据源库管理功能允许用户灵活选择和管理中国IP数据源，避免使用过多数据源导致的误拦截问题，提高系统的准确性和可靠性。

## 核心特性

### 🎯 灵活的数据源管理
- **启用/禁用控制**：可以单独启用或禁用每个数据源
- **自定义添加**：支持添加自定义的IP数据源
- **删除管理**：可以删除不需要的数据源
- **状态监控**：实时监控数据源的可用性状态

### 📊 智能选择机制
- **精简配置**：建议只使用1-2个最可靠的数据源
- **动态调整**：根据需求随时调整数据源配置
- **故障切换**：数据源故障时自动切换到可用数据源
- **性能优化**：减少数据源数量提高更新效率

### 🔧 完整的生命周期管理
- **初始化配置**：自动创建默认数据源配置
- **状态持久化**：配置变更自动保存
- **备份恢复**：支持配置的备份和恢复
- **版本控制**：跟踪配置变更历史

## 默认数据源

### IPv4数据源
1. **metowolf/IPList**
   - URL: https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt
   - 特点：更新频繁，准确性高
   - 推荐：作为主要数据源

2. **17mon/ChinaIPList**
   - URL: https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt
   - 特点：准确性高，覆盖全面
   - 推荐：作为验证数据源

3. **gaoyifan/OperatorIP**
   - URL: https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt
   - 特点：运营商数据，覆盖全面
   - 推荐：可选数据源

4. **misakaio/ChinaIP**
   - URL: https://raw.githubusercontent.com/misakaio/chnroutes2/master/chnroutes.txt
   - 特点：路由表数据，较为准确
   - 推荐：可选数据源

### IPv6数据源
1. **gaoyifan/ChinaIPv6**
   - URL: https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china6.txt
   - 特点：中国运营商IPv6地址列表
   - 推荐：如果需要IPv6支持

## 使用指南

### 进入数据源管理
```bash
# 运行主脚本
sudo ./port-filter-with-datasource.sh

# 在主菜单中选择选项11
选择菜单: 11
```

### 数据源管理菜单
```
==================== 数据源库管理 ====================
1.  查看数据源库
2.  启用/禁用数据源
3.  添加自定义数据源
4.  删除数据源
5.  测试数据源可用性
6.  重置为默认数据源
0.  返回主菜单

请选择操作 [0-6]: 
```

### 1. 查看数据源库
显示所有数据源的状态信息，包括：
- 数据源ID和名称
- IP类型（IPv4/IPv6）
- 启用状态（✓启用/✗禁用）
- 数据源描述
- 统计信息（启用的IPv4/IPv6数据源数量）

### 2. 启用/禁用数据源
允许用户动态启用或禁用特定的数据源：
```
# 操作步骤
1. 查看数据源列表，记住要操作的数据源ID
2. 选择启用/禁用功能
3. 输入数据源ID
4. 输入操作类型（enable/disable）
5. 确认操作

示例：
请输入要切换的数据源ID: 3
启用还是禁用？(enable/disable): disable
✓ 已将数据源 'gaoyifan/OperatorIP' 设置为: disabled
```

### 3. 添加自定义数据源
支持添加企业或个人的自定义IP数据源：
```
# 操作步骤
1. 选择添加自定义数据源功能
2. 输入数据源名称（不能重复）
3. 输入数据源URL
4. 选择IP类型（IPv4/IPv6）
5. 输入描述信息
6. 确认添加

示例：
数据源名称: EnterpriseIPList
数据源URL: https://enterprise.company.com/china-ip.txt
IP类型 (IPv4/IPv6): IPv4
描述信息: 企业内部的精确中国IP列表
✓ 已添加自定义数据源: EnterpriseIPList
```

### 4. 删除数据源
可以删除不再需要的数据源（谨慎操作）：
```
# 操作步骤
1. 查看数据源列表，记住要删除的数据源ID
2. 选择删除数据源功能
3. 输入数据源ID
4. 确认删除操作

示例：
请输入要删除的数据源ID: 4
确认删除？(y/N): y
✓ 已删除数据源: misakaio/ChinaIP
```

### 5. 测试数据源可用性
检测所有启用的数据源是否可用：
```
# 操作步骤
1. 选择测试数据源可用性功能
2. 系统自动测试所有启用的数据源
3. 显示测试结果

示例输出：
正在测试所有启用的数据源...
正在测试数据源: metowolf/IPList
✓ 数据源可用: metowolf/IPList
正在测试数据源: 17mon/ChinaIPList
✓ 数据源可用: 17mon/ChinaIPList
正在测试数据源: gaoyifan/ChinaIPv6
✓ 数据源可用: gaoyifan/ChinaIPv6

数据源测试结果：
启用数据源: 3
可用数据源: 3
不可用数据源: 0
```

### 6. 重置为默认数据源
将数据源配置重置为系统默认配置：
```
# 操作步骤
1. 选择重置为默认数据源功能
2. 确认重置操作
3. 系统将恢复所有默认数据源配置

示例：
确认重置为默认数据源？(y/N): y
✓ 已重置为默认数据源
```

## 最佳实践

### 推荐配置策略

#### 生产环境配置
```bash
# 高可靠性配置（推荐）
启用: metowolf/IPList (主要数据源)
启用: 17mon/ChinaIPList (验证数据源)
禁用: 其他所有IPv4数据源
启用: gaoyifan/ChinaIPv6 (如果需要IPv6)
```

#### 测试环境配置
```bash
# 全面测试配置
启用: metowolf/IPList
启用: 17mon/ChinaIPList
启用: gaoyifan/OperatorIP
启用: misakaio/ChinaIP
启用: gaoyifan/ChinaIPv6
```

#### 仅IPv4环境配置
```bash
# IPv4专用配置
启用: metowolf/IPList
启用: 17mon/ChinaIPList
禁用: gaoyifan/ChinaIPv6
禁用: 其他可选数据源
```

### 管理建议

1. **精选数据源**
   - 选择2-3个最可靠的数据源
   - 优先选择更新频繁的数据源
   - 考虑数据源的权威性和准确性

2. **定期维护**
   - 每周检测数据源可用性
   - 定期更新和审查数据源列表
   - 监控数据源的性能和准确性

3. **故障处理**
   - 保持至少2个数据源启用
   - 准备备用数据源配置
   - 记录数据源的历史表现

4. **自定义集成**
   - 添加企业内部的精确IP数据
   - 集成多个数据源进行交叉验证
   - 建立数据源的评估和评分机制

## 配置文件

### 数据源配置文件
- **文件路径**：`/etc/port-filter/datasources.conf`
- **格式说明**：每行一个数据源，格式为 `名称|URL|类型|描述|状态`
- **权限设置**：600（仅root可读写）

### 示例配置
```bash
# /etc/port-filter/datasources.conf
metowolf/IPList|https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt|IPv4|Metowolf的中国IP列表，更新频繁|enabled
17mon/ChinaIPList|https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt|IPv4|17mon的中国IP列表，准确性高|enabled
gaoyifan/OperatorIP|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt|IPv4|运营商IP列表，覆盖全面|disabled
misakaio/ChinaIP|https://raw.githubusercontent.com/misakaio/chnroutes2/master/chnroutes.txt|IPv4|MisakaIO的中国IP路由表|disabled
gaoyifan/ChinaIPv6|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china6.txt|IPv6|中国运营商IPv6地址列表|enabled
```

## 常见问题

### Q1: 为什么需要管理数据源？
**A1**: 使用过多数据源可能导致：
- IP地址重复和冲突
- 不一致的IP段定义
- 过时的IP信息
- 系统性能下降
- 误拦截概率增加

### Q2: 应该选择几个数据源？
**A2**: 推荐配置：
- 生产环境：2个数据源（1主1备）
- 测试环境：3-4个数据源（对比测试）
- 最小配置：1个数据源（资源受限环境）

### Q3: 如何添加自定义数据源？
**A3**: 自定义数据源要求：
- 纯文本格式，每行一个IP或IP段
- 支持IPv4和IPv6地址
- 支持CIDR格式
- 可以包含注释（以#开头）

### Q4: 数据源更新频率如何设置？
**A4**: 建议更新频率：
- 生产环境：每天1-2次
- 测试环境：每天多次
- 重要时期：每小时更新

### Q5: 如何验证数据源准确性？
**A5**: 验证方法：
- 使用多个数据源交叉验证
- 定期抽样测试IP归属
- 监控误拦截率变化
- 建立反馈和修正机制

## 故障排除

### 数据源不可用的处理
```bash
# 检查网络连接
ping -c 4 raw.githubusercontent.com

# 测试特定URL
curl -I https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt

# 禁用故障数据源
# 在数据源管理菜单中选择相应操作
```

### 自定义数据源格式错误
```bash
# 检查文件格式
curl -s https://your-server.com/china-ip.txt | head -10

# 验证IP格式
# 确保每行是有效的IP地址或CIDR格式
# 可以包含注释行（以#开头）
```

### 配置变更不生效
```bash
# 检查配置文件权限
ls -l /etc/port-filter/datasources.conf

# 重启脚本使配置生效
sudo ./port-filter-with-datasource.sh
```

## 技术实现

### 数据源管理架构
```
用户界面
    ↓
数据源管理模块
    ↓
配置文件操作
    ↓
IP列表下载模块
    ↓
IPSet更新
```

### 关键功能实现
- **配置文件管理**：使用分隔符格式存储数据源信息
- **状态控制**：通过enabled/disabled状态控制数据源使用
- **可用性检测**：使用HTTP HEAD请求检测数据源状态
- **错误处理**：优雅处理网络错误和数据格式错误

## 版本信息

### 当前版本：v2.3.0
- ✅ 数据源库管理功能
- ✅ 启用/禁用控制
- ✅ 自定义数据源添加
- ✅ 数据源删除功能
- ✅ 可用性检测
- ✅ 配置持久化
- ✅ 备份恢复支持

### 更新日志
- **v2.3.0**: 增加IP数据源库管理功能
- **v2.2.0**: 增加IP白名单功能
- **v2.1.0**: 系统监控和备份功能
- **v2.0.0**: 基础端口过滤功能

---

**重要提醒**：
1. 谨慎管理数据源配置
2. 定期备份配置文件
3. 测试自定义数据源格式
4. 监控数据源可用性
5. 建立故障处理预案