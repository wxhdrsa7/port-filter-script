#!/usr/bin/env python3
"""
简洁的端口过滤脚本
支持IP白名单、动态规则库管理
"""

import json
import os
import ipaddress
from datetime import datetime

class PortFilter:
    def __init__(self, config_file="config.json"):
        self.config_file = config_file
        self.config = self.load_config()
        self.whitelist = set(self.config.get("whitelist", []))
        self.active_rules = set(self.config.get("active_rules", []))
        self.rules = {}
        self.load_rules()
    
    def load_config(self):
        """加载配置文件"""
        if os.path.exists(self.config_file):
            with open(self.config_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {"whitelist": [], "active_rules": []}
    
    def save_config(self):
        """保存配置文件"""
        self.config["whitelist"] = list(self.whitelist)
        self.config["active_rules"] = list(self.active_rules)
        with open(self.config_file, 'w', encoding='utf-8') as f:
            json.dump(self.config, f, indent=2, ensure_ascii=False)
    
    def load_rules(self):
        """加载所有可用的规则库"""
        rules_dir = "rules"
        if not os.path.exists(rules_dir):
            os.makedirs(rules_dir)
            self.create_default_rules()
        
        for filename in os.listdir(rules_dir):
            if filename.endswith('.json'):
                rule_name = filename[:-5]
                try:
                    with open(os.path.join(rules_dir, filename), 'r', encoding='utf-8') as f:
                        self.rules[rule_name] = json.load(f)
                except Exception as e:
                    print(f"加载规则 {rule_name} 失败: {e}")
    
    def create_default_rules(self):
        """创建默认规则库"""
        default_rules = {
            "common_attacks": {
                "description": "常见攻击端口",
                "ports": [22, 23, 135, 139, 445, 1433, 3389],
                "severity": "high"
            },
            "malware_ports": {
                "description": "已知恶意软件端口",
                "ports": [135, 4444, 5554, 8866, 9996, 12345, 27374],
                "severity": "critical"
            },
            "scan_detection": {
                "description": "扫描检测端口",
                "ports": [1, 7, 9, 11, 15, 21, 25, 111, 135, 139, 445],
                "severity": "medium"
            }
        }
        
        for name, rule in default_rules.items():
            with open(f"rules/{name}.json", 'w', encoding='utf-8') as f:
                json.dump(rule, f, indent=2, ensure_ascii=False)
    
    def add_whitelist_ip(self, ip):
        """添加IP到白名单（支持单个IP或IP段）"""
        try:
            # 验证IP地址或IP段
            ipaddress.ip_network(ip, strict=False)
            self.whitelist.add(ip)
            self.save_config()
            print(f"已添加 {ip} 到白名单")
        except ValueError:
            print(f"无效的IP地址或IP段: {ip}")
    
    def remove_whitelist_ip(self, ip):
        """从白名单移除IP"""
        if ip in self.whitelist:
            self.whitelist.remove(ip)
            self.save_config()
            print(f"已从白名单移除 {ip}")
        else:
            print(f"{ip} 不在白名单中")
    
    def is_ip_whitelisted(self, ip):
        """检查IP是否在白名单中"""
        try:
            ip_obj = ipaddress.ip_address(ip)
            for whitelist_ip in self.whitelist:
                if ip_obj in ipaddress.ip_network(whitelist_ip, strict=False):
                    return True
            return False
        except ValueError:
            return False
    
    def list_available_rules(self):
        """列出所有可用的规则库"""
        print("\n可用的规则库:")
        for name, rule in self.rules.items():
            status = "✓ 已激活" if name in self.active_rules else "✗ 未激活"
            print(f"  {name}: {rule['description']} [{status}]")
            print(f"    端口: {rule['ports']}")
            print(f"    严重级别: {rule['severity']}")
    
    def activate_rule(self, rule_name):
        """激活规则库"""
        if rule_name in self.rules:
            self.active_rules.add(rule_name)
            self.save_config()
            print(f"已激活规则库: {rule_name}")
        else:
            print(f"规则库 {rule_name} 不存在")
    
    def deactivate_rule(self, rule_name):
        """停用规则库"""
        if rule_name in self.active_rules:
            self.active_rules.remove(rule_name)
            self.save_config()
            print(f"已停用规则库: {rule_name}")
        else:
            print(f"规则库 {rule_name} 未激活")
    
    def check_port(self, port, ip=None):
        """检查端口是否被规则拦截"""
        # 如果IP在白名单中，直接放行
        if ip and self.is_ip_whitelisted(ip):
            return False, "IP在白名单中"
        
        # 检查活跃规则
        blocked_by = []
        for rule_name in self.active_rules:
            if rule_name in self.rules and port in self.rules[rule_name]["ports"]:
                blocked_by.append(f"{rule_name}({self.rules[rule_name]['severity']})")
        
        if blocked_by:
            return True, f"被规则拦截: {', '.join(blocked_by)}"
        
        return False, "端口正常"
    
    def log_attempt(self, ip, port, action, reason):
        """记录日志"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] {ip}:{port} - {action} - {reason}\n"
        
        with open("filter.log", "a", encoding='utf-8') as f:
            f.write(log_entry)
    
    def show_whitelist(self):
        """显示白名单"""
        print("\n当前白名单:")
        if self.whitelist:
            for ip in sorted(self.whitelist):
                print(f"  {ip}")
        else:
            print("  白名单为空")
    
    def show_status(self):
        """显示当前状态"""
        print("\n=== 端口过滤器状态 ===")
        print(f"配置文件: {self.config_file}")
        print(f"白名单IP数量: {len(self.whitelist)}")
        print(f"可用规则库数量: {len(self.rules)}")
        print(f"激活的规则库数量: {len(self.active_rules)}")
        
        self.show_whitelist()
        self.list_available_rules()

def main():
    """主函数 - 简单的命令行界面"""
    filter = PortFilter()
    
    print("端口过滤脚本 - 简洁版")
    print("=" * 40)
    
    while True:
        print("\n命令选项:")
        print("  1. 显示状态")
        print("  2. 添加IP到白名单")
        print("  3. 从白名单移除IP")
        print("  4. 激活规则库")
        print("  5. 停用规则库")
        print("  6. 检查端口")
        print("  7. 退出")
        
        choice = input("\n选择操作 (1-7): ").strip()
        
        if choice == "1":
            filter.show_status()
        
        elif choice == "2":
            ip = input("输入要添加到白名单的IP或IP段: ").strip()
            filter.add_whitelist_ip(ip)
        
        elif choice == "3":
            ip = input("输入要从白名单移除的IP: ").strip()
            filter.remove_whitelist_ip(ip)
        
        elif choice == "4":
            filter.list_available_rules()
            rule_name = input("输入要激活的规则库名称: ").strip()
            filter.activate_rule(rule_name)
        
        elif choice == "5":
            filter.list_available_rules()
            rule_name = input("输入要停用的规则库名称: ").strip()
            filter.deactivate_rule(rule_name)
        
        elif choice == "6":
            try:
                port = int(input("输入要检查的端口号: ").strip())
                ip = input("输入IP地址（可选，直接回车跳过）: ").strip()
                blocked, reason = filter.check_port(port, ip if ip else None)
                print(f"结果: {'拦截' if blocked else '放行'} - {reason}")
                
                # 记录日志
                filter.log_attempt(ip or "unknown", port, "BLOCK" if blocked else "ALLOW", reason)
            except ValueError:
                print("请输入有效的端口号")
        
        elif choice == "7":
            print("退出程序")
            break
        
        else:
            print("无效选择，请重新输入")

if __name__ == "__main__":
    main()