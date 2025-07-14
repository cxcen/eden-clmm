/// 费用等级管理模块
/// FeeTiers信息提供创建池子时使用的费用等级元数据
/// FeeTier存储在部署账户(@eden_clmm)中
/// FeeTier通过tick_spacing来标识
/// FeeTier只能由协议创建和更新

module eden_clmm::fee_tier {
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use eden_clmm::config;

   // 最大交换费率(100000 = 200000/1000000 = 20%)
    const MAX_FEE_RATE: u64 = 200000;

   // 错误代码
    const EFEE_TIER_ALREADY_EXIST: u64 = 1; // 费用等级已存在
    const EFEE_TIER_NOT_FOUND: u64 = 2; // 费用等级未找到
    const EFEETIER_ALREADY_INITIALIZED: u64 = 3; // 费用等级已初始化
    const EINVALID_FEE_RATE: u64 = 4; // 无效的费率
    const EINVALID_TICK_SPACE: u64 = 5; // 无效的间隔

   // CLMM池的费用等级数据结构
    struct FeeTier has store, copy, drop {
       // tick间距
        tick_spacing: u64,

       // 默认费率
        fee_rate: u64
    }

   // CLMM池的费用等级映射表
    struct FeeTiers has key {
        fee_tiers: SimpleMap<u64, FeeTier>, // tick_spacing到FeeTier的映射
        add_events: EventHandle<AddEvent>, // 添加事件
        update_events: EventHandle<UpdateEvent>, // 更新事件
        delete_events: EventHandle<DeleteEvent> // 删除事件
    }

   // 添加费用等级事件
    struct AddEvent has drop, store {
        tick_spacing: u64,
        fee_rate: u64
    }

   // 更新费用等级事件
    struct UpdateEvent has drop, store {
        tick_spacing: u64,
        old_fee_rate: u64,
        new_fee_rate: u64
    }

   // 删除费用等级事件
    struct DeleteEvent has drop, store {
        tick_spacing: u64
    }

   // 初始化Eden CLMM协议的全局FeeTier
   // 参数：account - 签名者账户
    public fun initialize(account: &signer) {
        config::assert_initialize_authority(account);
        move_to(
            account,
            FeeTiers {
                fee_tiers: simple_map::create<u64, FeeTier>(),
                add_events: account::new_event_handle<AddEvent>(account),
                update_events: account::new_event_handle<UpdateEvent>(account),
                delete_events: account::new_event_handle<DeleteEvent>(account)
            }
        );
    }

   // 添加费用等级
   // 参数：account - 协议权限账户，tick_spacing - tick间距，fee_rate - 费率
    public fun add_fee_tier(account: &signer, tick_spacing: u64, fee_rate: u64) acquires FeeTiers {
        assert!(fee_rate <= MAX_FEE_RATE, EINVALID_FEE_RATE);
        assert!(tick_spacing % config::tick_space_factor() == 0, EINVALID_TICK_SPACE);

        config::assert_protocol_authority(account);
        let fee_tiers = borrow_global_mut<FeeTiers>(@eden_clmm);
        assert!(!fee_tiers.fee_tiers.contains_key(&tick_spacing), EFEE_TIER_ALREADY_EXIST);
        fee_tiers.fee_tiers.add(tick_spacing, FeeTier { tick_spacing, fee_rate });
        event::emit_event(
            &mut fee_tiers.add_events,
            AddEvent { tick_spacing, fee_rate }
        )
    }

   // 更新默认费率
   // 参数：account - 协议权限账户，tick_spacing - tick间距，new_fee_rate - 新费率
    public fun update_fee_tier(
        account: &signer,
        tick_spacing: u64,
        new_fee_rate: u64
    ) acquires FeeTiers {
        assert!(new_fee_rate <= MAX_FEE_RATE, EINVALID_FEE_RATE);

        config::assert_protocol_authority(account);
        let fee_tiers = borrow_global_mut<FeeTiers>(@eden_clmm);
        assert!(
            fee_tiers.fee_tiers.contains_key(&tick_spacing),
            EFEE_TIER_NOT_FOUND
        );

        let fee_tier = fee_tiers.fee_tiers.borrow_mut(&tick_spacing);
        let old_fee_rate = fee_tier.fee_rate;
        fee_tier.fee_rate = new_fee_rate;
        event::emit_event(
            &mut fee_tiers.update_events,
            UpdateEvent { tick_spacing, old_fee_rate, new_fee_rate }
        );
    }

   // 删除费用等级
   // 参数：account - 协议权限账户，tick_spacing - tick间距
    public fun delete_fee_tier(account: &signer, tick_spacing: u64) acquires FeeTiers {
        config::assert_protocol_authority(account);
        let fee_tiers = borrow_global_mut<FeeTiers>(@eden_clmm);
        assert!(
            fee_tiers.fee_tiers.contains_key(&tick_spacing),
            EFEE_TIER_NOT_FOUND
        );
        fee_tiers.fee_tiers.remove(&tick_spacing);
        event::emit_event(&mut fee_tiers.delete_events, DeleteEvent { tick_spacing });
    }

   // 根据tick间距获取费率
   // 参数：tick_spacing - tick间距
   // 返回：对应的费率
    public fun get_fee_rate(tick_spacing: u64): u64 acquires FeeTiers {
        let fee_tiers = &borrow_global<FeeTiers>(@eden_clmm).fee_tiers;
        assert!(
            fee_tiers.contains_key(&tick_spacing),
            EFEE_TIER_NOT_FOUND
        );
        let fee_tier = fee_tiers.borrow(&tick_spacing);
        fee_tier.fee_rate
    }

   // 获取最大费率
   // 返回：最大费率值
    public fun max_fee_rate(): u64 {
        MAX_FEE_RATE
    }
}
