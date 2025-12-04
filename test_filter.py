#!/usr/bin/env python3
"""
端口过滤测试脚本
"""

from port_filter import PortFilter

def test_port_filter():
    """测试端口过滤功能"""
    print("开始测试端口过滤功能...")
    
    # 创建过滤器实例
    pf = PortFilter("test_config.json")
    
    # 测试1: 添加白名单IP
    print("\n1. 测试白名单功能")
    pf.add_whitelist_ip("192.168.1.100")
    pf.add_whitelist_ip("10.0.0.0/8")
    
    # 测试2: 激活规则库
    print("\n2. 测试规则库激活")
    pf.activate_rule("common_attacks")
    pf.activate_rule("malware_ports")
    
    # 测试3: 端口检查
    print("\n3. 测试端口检查")
    test_cases = [
        (22, "192.168.1.100"),    # 白名单IP，应该放行
        (22, "10.0.0.1"),         # 白名单网段，应该放行
        (22, "172.16.0.1"),       # 非白名单，应该拦截
        (3389, "192.168.1.100"),  # 白名单IP，应该放行
        (3389, "203.0.113.1"),    # 非白名单，应该拦截
    ]
    
    for port, ip in test_cases:
        blocked, reason = pf.check_port(port, ip)
        status = "拦截" if blocked else "放行"
        print(f"  端口 {port} IP {ip}: {status} - {reason}")
    
    # 测试4: 停用规则库
    print("\n4. 测试规则库停用")
    pf.deactivate_rule("common_attacks")
    
    # 再次测试端口
    print("\n5. 停用规则库后再次测试")
    blocked, reason = pf.check_port(22, "203.0.113.1")
    status = "拦截" if blocked else "放行"
    print(f"  端口 22 IP 203.0.113.1: {status} - {reason}")
    
    # 显示最终状态
    print("\n6. 最终状态")
    pf.show_status()
    
    print("\n测试完成！")

if __name__ == "__main__":
    test_port_filter()