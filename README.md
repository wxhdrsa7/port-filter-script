# 🧱 Port Filter Script

一键配置服务器端口访问规则，支持国内/国际分流、端口屏蔽放行、自动计划更新等功能。

## ✨ 功能特性
- ✅ 国内/国际 IP 地域过滤（黑名单、白名单）
- ✅ 一键屏蔽或放行指定端口（支持 TCP / UDP / 双协议）
- ✅ 多源中国 IP 列表聚合导入，规则更全面
- ✅ 支持计划任务，自动定时更新 IP 数据
- ✅ 彩色交互菜单，SSH 终端友好
- ✅ iptables/ipset 规则持久化保存
- ✅ 提供 `--update-ip` 命令行参数供计划任务调用

## 📦 菜单功能概览
| 序号 | 功能 | 说明 |
| ---- | ---- | ---- |
| 1 | IP 地域过滤 | 选择端口、协议，设置黑名单（阻止国内）或白名单（只允许国内） |
| 2 | 屏蔽端口 | 完全阻断指定端口访问 |
| 3 | 放行端口 | 完全放通指定端口 |
| 4 | 查看 iptables 规则 | 快速检查当前防火墙规则（前 20 条） |
| 5 | 清除所有规则 | 移除所有本脚本添加的规则、计划任务与配置 |
| 6 | 立即更新中国 IP | 手动刷新多源中国 IP 列表 |
| 7 | 配置自动更新 | 设置每天的自动更新时间（24 小时制） |
| 8 | 查看已保存的策略 | 以表格形式查看通过脚本设置的端口策略 |

## ⏱ 自动更新计划
- 可在菜单中选择“配置自动更新计划”设定每天的更新时间，如 `03:30`
- 创建的计划任务位于 `/etc/cron.d/port-filter`
- 更新日志默认输出至 `/var/log/port-filter/update.log`
- 计划任务实际执行的命令：`/usr/local/bin/port-filter --update-ip`

## ⚙️ 命令行模式
脚本支持直接从命令行调用以便计划任务或手动刷新：
```bash
sudo /usr/local/bin/port-filter --update-ip
```

## 🚀 安装
```bash
bash <(curl -sL https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/install.sh)
```

## 🔧 手动运行
```bash
sudo port-filter
```

## 🧹 卸载
```bash
sudo rm -f /usr/local/bin/port-filter
sudo iptables -F INPUT
sudo ipset destroy china 2>/dev/null
```
