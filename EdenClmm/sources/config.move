/// 全局配置管理模块
/// 全局配置只初始化一次，存储协议权限、协议费用领取权限、
/// 池子创建权限和协议费率。
/// 协议权限控制整个协议，可以更新协议费用领取权限、池子创建权限和
/// 协议费率，并且可以转移给其他人。
module eden_clmm::config {
    use std::signer;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use eden_clmm::acl::{Self, ACL};

    friend eden_clmm::factory;

   // 常量定义
    const DEFAULT_ADDRESS: address = @0x0; // 默认地址
    const MAX_PROTOCOL_FEE_RATE: u64 = 3000; // 最大协议费率
    const DEFAULT_PROTOCOL_FEE_RATE: u64 = 2000; // 默认协议费率

   // 错误代码
    const ENOT_HAS_PRIVILEGE: u64 = 1; // 没有权限
    const ECONFIG_ALREADY_INITIALIZED: u64 = 2; // 配置已经初始化
    const EINVALID_PROTOCOL_FEE_RATE: u64 = 3; // 无效的协议费率
    const EPROTOCOL_IS_PAUSED: u64 = 4; // 协议已暂停
    const EINVALID_ACL_ROLE: u64 = 5; // 无效的ACL角色

   // 角色定义
    const ROLE_SET_POSITION_NFT_URI: u8 = 1; // 设置位置NFT URI的角色
    const ROLE_RESET_INIT_SQRT_PRICE: u8 = 2; // 重置初始sqrt价格的角色

   // CLMM池的全局配置
    struct GlobalConfig has key {
       // 控制配置和与此CLMM配置相关的CLMM池的权限
        protocol_authority: address,

       // `protocol_pending_authority` 在转移协议权限时使用，
       // 存储下一步要接受的新权限作为新权限
        protocol_pending_authority: address,

       // `protocol_fee_claim_authority` 在领取协议费用时使用
        protocol_fee_claim_authority: address,

       // `pool_create_authority` 在创建池时使用。如果此地址是默认地址，
       // 意味着任何人都可以创建池
        pool_create_authority: address,

       // `fee_rate` 协议费率
        protocol_fee_rate: u64,

       // 协议是否暂停
        is_pause: bool,

       // 事件句柄
        transfer_auth_events: EventHandle<TransferAuthEvent>, // 转移权限事件
        accept_auth_events: EventHandle<AcceptAuthEvent>, // 接受权限事件
        update_claim_auth_events: EventHandle<UpdateClaimAuthEvent>, // 更新领取权限事件
        update_pool_create_events: EventHandle<UpdatePoolCreateEvent>, // 更新池创建事件
        update_fee_rate_events: EventHandle<UpdateFeeRateEvent> // 更新费率事件
    }

   // CLMM访问控制列表
    struct ClmmACL has key {
        acl: ACL
    }

   // 事件结构体定义

   // 转移权限事件
    struct TransferAuthEvent has drop, store {
        old_auth: address, // 旧权限地址
        new_auth: address // 新权限地址
    }

   // 接受权限事件
    struct AcceptAuthEvent has drop, store {
        old_auth: address, // 旧权限地址
        new_auth: address // 新权限地址
    }

   // 更新领取权限事件
    struct UpdateClaimAuthEvent has drop, store {
        old_auth: address, // 旧权限地址
        new_auth: address // 新权限地址
    }

   // 更新池创建事件
    struct UpdatePoolCreateEvent has drop, store {
        old_auth: address, // 旧权限地址
        new_auth: address // 新权限地址
    }

   // 更新费率事件
    struct UpdateFeeRateEvent has drop, store {
        old_fee_rate: u64, // 旧费率
        new_fee_rate: u64 // 新费率
    }

   // 初始化Eden CLMM协议的全局配置
   // 参数：account - 部署账户
    public fun initialize(account: &signer) {
        assert_initialize_authority(account);
        let deployer = @eden_clmm;
        move_to(
            account,
            GlobalConfig {
                protocol_authority: deployer,
                protocol_pending_authority: DEFAULT_ADDRESS,
                protocol_fee_claim_authority: deployer,
                pool_create_authority: DEFAULT_ADDRESS,
                protocol_fee_rate: DEFAULT_PROTOCOL_FEE_RATE,
                is_pause: false,
                transfer_auth_events: account::new_event_handle<TransferAuthEvent>(
                    account
                ),
                accept_auth_events: account::new_event_handle<AcceptAuthEvent>(account),
                update_claim_auth_events: account::new_event_handle<UpdateClaimAuthEvent>(
                    account
                ),
                update_pool_create_events: account::new_event_handle<UpdatePoolCreateEvent>(
                    account
                ),
                update_fee_rate_events: account::new_event_handle<UpdateFeeRateEvent>(
                    account
                )
            }
        );
    }

   // 转移协议权限
   // 参数：account - 当前协议权限账户，protocol_authority - 新的协议权限地址
    public fun transfer_protocol_authority(
        account: &signer, protocol_authority: address
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@eden_clmm);
        global_config.protocol_pending_authority = protocol_authority;
        event::emit_event(
            &mut global_config.transfer_auth_events,
            TransferAuthEvent {
                old_auth: global_config.protocol_authority,
                new_auth: protocol_authority
            }
        );
    }

   // 接受协议权限
   // 参数：account - 新的协议权限账户
    public fun accept_protocol_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global_mut<GlobalConfig>(@eden_clmm);
        assert!(
            global_config.protocol_pending_authority == signer::address_of(account),
            ENOT_HAS_PRIVILEGE
        );
        let old_auth = global_config.protocol_authority;
        global_config.protocol_authority = signer::address_of(account);
        global_config.protocol_pending_authority = DEFAULT_ADDRESS;
        event::emit_event(
            &mut global_config.accept_auth_events,
            AcceptAuthEvent { old_auth, new_auth: global_config.protocol_authority }
        );
    }

   // 更新协议费用领取权限
   // 参数：account - 协议权限账户，protocol_fee_claim_authority - 新的费用领取权限地址
    public fun update_protocol_fee_claim_authority(
        account: &signer, protocol_fee_claim_authority: address
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@eden_clmm);
        let old_auth = global_config.protocol_fee_claim_authority;
        global_config.protocol_fee_claim_authority = protocol_fee_claim_authority;
        event::emit_event(
            &mut global_config.update_claim_auth_events,
            UpdateClaimAuthEvent {
                old_auth,
                new_auth: global_config.protocol_fee_claim_authority
            }
        );
    }

   // 更新池创建权限
   // 参数：account - 协议权限账户，pool_create_authority - 新的池创建权限地址
    public fun update_pool_create_authority(
        account: &signer, pool_create_authority: address
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@eden_clmm);
        let old_auth = global_config.pool_create_authority;
        global_config.pool_create_authority = pool_create_authority;
        event::emit_event(
            &mut global_config.update_pool_create_events,
            UpdatePoolCreateEvent {
                old_auth,
                new_auth: global_config.pool_create_authority
            }
        );
    }

   // 更新协议费率
   // 参数：account - 协议权限账户，protocol_fee_rate - 新的协议费率
    public fun update_protocol_fee_rate(
        account: &signer, protocol_fee_rate: u64
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        assert!(protocol_fee_rate <= MAX_PROTOCOL_FEE_RATE, EINVALID_PROTOCOL_FEE_RATE);
        let global_config = borrow_global_mut<GlobalConfig>(@eden_clmm);
        let old_fee_rate = global_config.protocol_fee_rate;
        global_config.protocol_fee_rate = protocol_fee_rate;
        event::emit_event(
            &mut global_config.update_fee_rate_events,
            UpdateFeeRateEvent { old_fee_rate, new_fee_rate: protocol_fee_rate }
        );
    }

   // 暂停协议
   // 参数：account - 协议权限账户
    public fun pause(account: &signer) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@eden_clmm);
        global_config.is_pause = true;
    }

   // 取消暂停协议
   // 参数：account - 协议权限账户
    public fun unpause(account: &signer) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@eden_clmm);
        global_config.is_pause = false;
    }

   // 断言协议状态（检查是否暂停）
    public fun assert_protocol_status() acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@eden_clmm);
        if (global_config.is_pause) {
            abort EPROTOCOL_IS_PAUSED
        }
    }

   // 获取协议费率
   // 返回值：协议费率
    public fun get_protocol_fee_rate(): u64 acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@eden_clmm);
        global_config.protocol_fee_rate
    }

   // 断言初始化权限
   // 参数：account - 待验证的账户
    public fun assert_initialize_authority(account: &signer) {
        assert!(
            signer::address_of(account) == @eden_clmm,
            ENOT_HAS_PRIVILEGE
        );
    }

   // 断言协议权限
   // 参数：account - 待验证的账户
    public fun assert_protocol_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@eden_clmm);
        assert!(
            global_config.protocol_authority == signer::address_of(account),
            ENOT_HAS_PRIVILEGE
        );
    }

   // 断言协议费用领取权限
   // 参数：account - 待验证的账户
    public fun assert_protocol_fee_claim_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@eden_clmm);
        assert!(
            global_config.protocol_fee_claim_authority == signer::address_of(account),
            ENOT_HAS_PRIVILEGE
        );
    }

   // 断言池创建权限
   // 参数：account - 待验证的账户
    public fun assert_pool_create_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@eden_clmm);
        assert!(
            (
                global_config.pool_create_authority == signer::address_of(account)
                    || global_config.pool_create_authority == DEFAULT_ADDRESS
            ),
            ENOT_HAS_PRIVILEGE
        );
    }

   // 初始化CLMM访问控制列表
   // 参数：account - 初始化账户
    public fun init_clmm_acl(account: &signer) {
        assert_initialize_authority(account);
        move_to(account, ClmmACL { acl: acl::new() })
    }

   // 添加角色
   // 参数：account - 协议权限账户，member - 成员地址，role - 角色值
    public fun add_role(account: &signer, member: address, role: u8) acquires GlobalConfig, ClmmACL {
        assert!(
            role == ROLE_SET_POSITION_NFT_URI || role == ROLE_RESET_INIT_SQRT_PRICE,
            EINVALID_ACL_ROLE
        );
        assert_protocol_authority(account);
        let clmm_acl = borrow_global_mut<ClmmACL>(@eden_clmm);
        acl::add_role(&mut clmm_acl.acl, member, role)
    }

   // 移除角色
   // 参数：account - 协议权限账户，member - 成员地址，role - 角色值
    public fun remove_role(account: &signer, member: address, role: u8) acquires GlobalConfig, ClmmACL {
        assert!(
            role == ROLE_SET_POSITION_NFT_URI || role == ROLE_RESET_INIT_SQRT_PRICE,
            EINVALID_ACL_ROLE
        );
        assert_protocol_authority(account);
        let clmm_acl = borrow_global_mut<ClmmACL>(@eden_clmm);
        acl::remove_role(&mut clmm_acl.acl, member, role)
    }

   // 检查是否允许设置位置NFT URI
   // 参数：account - 待验证的账户
   // 返回值：是否有权限
    public fun allow_set_position_nft_uri(account: &signer): bool acquires ClmmACL {
        let clmm_acl = borrow_global<ClmmACL>(@eden_clmm);
        acl::has_role(
            &clmm_acl.acl, signer::address_of(account), ROLE_SET_POSITION_NFT_URI
        )
    }

   // 断言重置初始价格权限
   // 参数：account - 待验证的账户
    public fun assert_reset_init_price_authority(account: &signer) acquires ClmmACL {
        let clmm_acl = borrow_global<ClmmACL>(@eden_clmm);
        if (!acl::has_role(
            &clmm_acl.acl, signer::address_of(account), ROLE_RESET_INIT_SQRT_PRICE
        )) {
            abort ENOT_HAS_PRIVILEGE
        }
    }
}
