# 🧱 Port Filter Script

一键设置防火墙端口过滤规则，支持多国家/地区 IP 集合、端口屏蔽/放行与规则持久化。

## ✨ 功能特性
- ✅ 多国家/地区 IP 地域过滤（黑/白名单）
- ✅ 自定义组合常见地区（中国、香港、欧美、东南亚等）
- ✅ 端口屏蔽/放行（支持 TCP / UDP / 双协议）
- ✅ 规则持久化保存，启动自动恢复
- ✅ 可视化规则列表与单条规则删除
- ✅ 一键更新国家/地区 IP 数据缓存
- ✅ 内置国内运营商/骨干网络列表，减少遗漏
- ✅ 一键配置自动更新任务，支持周期刷新
- ✅ 支持命令行模式（`--refresh-rules` / `--refresh-cache`）方便脚本化
- ✅ 改进彩色交互界面，SSH 终端友好

## 🚀 一键安装命令
```bash
bash <(curl -sL https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/install.sh)
🔧 手动运行
sudo port-filter

## 🛠️ 高级用法

### 自动刷新地域规则

1. 运行脚本后，进入菜单中的「设置自动更新」。
2. 选择合适的频率（每 6 小时 / 每日 / 每周），脚本会在 `/etc/cron.d/` 写入计划任务。
3. 日志输出位于 `/etc/port-filter/auto-update.log`，方便排查。

也可以通过命令行直接刷新：

```bash
sudo port-filter --refresh-rules   # 强制更新所有地域规则数据并重新加载
sudo port-filter --refresh-cache   # 仅刷新已配置地域规则的 IP 数据缓存
```

🧹 卸载
sudo rm -f /usr/local/bin/port-filter
sudo iptables -F INPUT
sudo ipset list -name | grep '^pf_geo_' | xargs -r -n1 sudo ipset destroy
