/// 访问控制列表（ACL）模块
/// Fork @https://github.com/pentagonxyz/movemate.git
/// 提供基于角色的访问控制功能，每个地址可以拥有多个角色（用位表示）
module eden_clmm::acl {

    use std::error;
    use aptos_framework::table::{Self, Table};

   // 错误：尝试添加/删除角色编号 >= 128 时触发
    const EROLE_NUMBER_TOO_LARGE: u64 = 0;

   // 访问控制列表结构体
   // 将地址映射到u128，每个位代表是否拥有对应的角色
    struct ACL has store {
        permissions: Table<address, u128> // 地址到权限位图的映射
    }

   // 创建新的ACL（访问控制列表）
   // 返回：新的ACL实例
    public fun new(): ACL {
        ACL { permissions: table::new() }
    }

   // 检查成员是否在ACL中拥有特定角色
   // 参数：acl - ACL引用，member - 成员地址，role - 角色编号（0-127）
   // 返回：如果拥有该角色返回true，否则返回false
    public fun has_role(acl: &ACL, member: address, role: u8): bool {
        assert!(role < 128, error::invalid_argument(EROLE_NUMBER_TOO_LARGE));
        acl.permissions.contains(member)
            && *acl.permissions.borrow(member) & (1 << role) > 0
    }

   // 为ACL中的成员设置所有角色
   // 参数：acl - ACL可变引用，member - 成员地址，permissions - 权限位图
   // 其中permissions是一个u128，每个位代表是否拥有对应的角色
    public fun set_roles(
        acl: &mut ACL, member: address, permissions: u128
    ) {
        if (acl.permissions.contains(member))
            *acl.permissions.borrow_mut(member) = permissions
        else
            acl.permissions.add(member, permissions);
    }

   // 为ACL中的成员添加一个角色
   // 参数：acl - ACL可变引用，member - 成员地址，role - 角色编号（0-127）
    public fun add_role(acl: &mut ACL, member: address, role: u8) {
        assert!(role < 128, error::invalid_argument(EROLE_NUMBER_TOO_LARGE));
        if (acl.permissions.contains(member)) {
            let perms = acl.permissions.borrow_mut(member);
            *perms |= (1 << role); // 使用按位或操作添加角色
        } else {
            acl.permissions.add(member, 1 << role);
        }
    }

   // 为ACL中的成员撤销一个角色
   // 参数：acl - ACL可变引用，member - 成员地址，role - 角色编号（0-127）
    public fun remove_role(acl: &mut ACL, member: address, role: u8) {
        assert!(role < 128, error::invalid_argument(EROLE_NUMBER_TOO_LARGE));
        if (acl.permissions.contains(member)) {
            let perms = acl.permissions.borrow_mut(member);
            *perms -= (1 << role); // 使用减法操作移除角色
        }
    }

    #[test_only]
   // 测试用的ACL结构体
    struct TestACL has key {
        acl: ACL
    }

    #[test(dummy = @0x1234)]
   // 端到端测试函数
   // 测试ACL的各种操作：添加角色、移除角色、设置角色等
    fun test_end_to_end(dummy: signer) {
        let acl = new();
        add_role(&mut acl, @0x1234, 12); // 添加角色12
        add_role(&mut acl, @0x1234, 99); // 添加角色99
        add_role(&mut acl, @0x1234, 88); // 添加角色88
        add_role(&mut acl, @0x1234, 123); // 添加角色123
        add_role(&mut acl, @0x1234, 2); // 添加角色2
        add_role(&mut acl, @0x1234, 1); // 添加角色1
        remove_role(&mut acl, @0x1234, 2); // 移除角色2
        // 为地址0x5678设置角色123、2、1
        set_roles(&mut acl, @0x5678, (1 << 123) | (1 << 2) | (1 << 1));
        let i = 0;
        // 遍历所有可能的角色（0-127）进行验证
        while (i < 128) {
            let has = has_role(&acl, @0x1234, i);
            // 验证地址0x1234应该拥有角色12、99、88、123、1
            assert!(
                if (i == 12 || i == 99 || i == 88 || i == 123 || i == 1) has
                else !has,
                0
            );
            has = has_role(&acl, @0x5678, i);
            // 验证地址0x5678应该拥有角色123、2、1
            assert!(if (i == 123 || i == 2 || i == 1) has else !has, 1);
            i += 1;
        };

        // 无法直接丢弃ACL，必须存储
        move_to(&dummy, TestACL { acl });
    }
}
