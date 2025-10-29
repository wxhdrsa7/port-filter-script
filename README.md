# 🧱 Port Filter Script

专为「国内来源控制」设计的端口过滤脚本，可一键实现：

- 某个端口禁止中国大陆来源访问
- 某个端口仅允许中国大陆来源访问
- 支持 TCP / UDP / 双协议
- 多源国内 IP 库自动合并 & 定时更新
- 彩色交互界面，SSH 终端友好

## ✨ 功能特性
- ✅ 国内 IP 库聚合：整合 metowolf、17mon、gaoyifan 三套规则
- ✅ 一键更新国内 IP 集合，并写入 ipset
- ✅ 端口规则持久化保存，系统重启后自动恢复
- ✅ 针对端口的「阻止国内访问」与「仅允许国内访问」双模式
- ✅ TCP / UDP / 双协议随选
- ✅ 自定义每日自动更新时间（cron），并写入日志
- ✅ 彩色菜单、兼容 SSH 终端

## 🚀 安装与启动
```bash
sudo bash install.sh
```
或使用一键安装脚本（适合远程执行）：

```bash
bash <(curl -sL https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/install.sh)
```

安装脚本会将 `port-filter.sh` 安装到 `/usr/local/bin/port-filter` 并立即启动交互界面。

## 🕹 使用指南
1. 「更新国内 IP 库」：从多个数据源下载并写入 `ipset`。
2. 「新增规则」：
   - 选择阻止/仅允许国内来源
   - 输入端口与协议
   - 规则将自动写入 `/etc/port-filter/rules.conf` 并立即生效
3. 「删除规则」：支持按编号移除指定端口策略。
4. 「设置自动更新」：输入 24 小时制时间（HH:MM），脚本会在 `/etc/cron.d/port-filter` 写入计划任务。

国内 IP 数据缓存及日志：
- 国内 IP 列表：`/etc/port-filter/cache/cn_ipv4.list`
- 自动更新日志：`/etc/port-filter/auto-update.log`

## 🧹 卸载说明
```bash
sudo rm -f /usr/local/bin/port-filter
sudo rm -rf /etc/port-filter
sudo rm -f /etc/cron.d/port-filter
sudo iptables -F PORT_FILTER
sudo iptables -D INPUT -j PORT_FILTER 2>/dev/null || true
sudo iptables -X PORT_FILTER 2>/dev/null || true
sudo ipset destroy pf_cn_ipv4 2>/dev/null || true
```
