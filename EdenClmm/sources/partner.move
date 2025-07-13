/// 合作伙伴模块
/// 合作伙伴模块为第三方提供分享协议费用的能力，当通过CLMM池进行交换时。
/// 合作伙伴由协议创建和控制。
/// 合作伙伴通过名称标识。
/// 合作伙伴通过开始时间和结束时间验证有效性。
/// 合作伙伴费用由接收者接收。
/// 接收者可以将接收者地址转移给其他地址。
/// 合作伙伴费率、开始时间和结束时间可以由协议更新。
module eden_clmm::partner {
    use std::string::String;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::event::EventHandle;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_std::table::Table;
    use aptos_std::table;
    use aptos_framework::object::Object;
    use aptos_framework::primary_fungible_store;
    use eden_clmm::config;

   // 常量定义
    const PARTNER_RATE_DENOMINATOR: u64 = 10000; // 合作伙伴费率分母
    const DEFAULT_ADDRESS: address = @0x0; // 默认地址
    const MAX_PARTNER_FEE_RATE: u64 = 10000; // 最大合作伙伴费率

   // 错误代码
    const EPARTNER_ALREADY_INITIALIZED: u64 = 1; // 合作伙伴已初始化
    const EPARTNER_ALREADY_EXISTED: u64 = 2; // 合作伙伴已存在
    const EPARTNER_NOT_EXISTED: u64 = 3; // 合作伙伴不存在
    const EINVALID_RECEIVER: u64 = 4; // 无效的接收者
    const EINVALID_TIME: u64 = 5; // 无效的时间
    const EINVALID_PARTNER_FEE_RATE: u64 = 6; // 无效的合作伙伴费率
    const EINVALID_PARTNER_NAME: u64 = 7; // 无效的合作伙伴名称

   // 合作伙伴集合
    struct Partners has key {
        data: Table<String, Partner>, // 合作伙伴数据表
        create_events: EventHandle<CreateEvent>, // 创建事件
        update_fee_rate_events: EventHandle<UpdateFeeRateEvent>, // 更新费率事件
        update_time_events: EventHandle<UpdateTimeEvent>, // 更新时间事件
        transfer_receiver_events: EventHandle<TransferReceiverEvent>, // 转移接收者事件
        accept_receiver_events: EventHandle<AcceptReceiverEvent>, // 接受接收者事件
        receive_ref_fee_events: EventHandle<ReceiveRefFeeEvent>, // 接收推荐费事件
        claim_ref_fee_events: EventHandle<ClaimRefFeeEvent> // 领取推荐费事件
    }

   // 合作伙伴元数据
    struct PartnerMetadata has store, copy, drop {
        partner_address: address, // 合作伙伴地址
        receiver: address, // 接收者地址
        pending_receiver: address, // 待接受的接收者地址
        fee_rate: u64, // 费率
        start_time: u64, // 开始时间
        end_time: u64 // 结束时间
    }

   // 合作伙伴结构体
    struct Partner has store {
        metadata: PartnerMetadata, // 元数据
        signer_capability: account::SignerCapability // 签名能力
    }

   // 事件结构体定义

   // 创建事件
    struct CreateEvent has drop, store {
        partner_address: address, // 合作伙伴地址
        fee_rate: u64, // 费率
        name: String, // 名称
        receiver: address, // 接收者地址
        start_time: u64, // 开始时间
        end_time: u64 // 结束时间
    }

   // 更新费率事件
    struct UpdateFeeRateEvent has drop, store {
        name: String, // 名称
        old_fee_rate: u64, // 旧费率
        new_fee_rate: u64 // 新费率
    }

   // 更新时间事件
    struct UpdateTimeEvent has drop, store {
        name: String, // 名称
        start_time: u64, // 开始时间
        end_time: u64 // 结束时间
    }

   // 转移接收者事件
    struct TransferReceiverEvent has drop, store {
        name: String, // 名称
        old_receiver: address, // 旧接收者地址
        new_receiver: address // 新接收者地址
    }

   // 接受接收者事件
    struct AcceptReceiverEvent has drop, store {
        name: String, // 名称
        receiver: address // 接收者地址
    }

   // 接收推荐费事件
    struct ReceiveRefFeeEvent has drop, store {
        name: String, // 名称
        amount: u64, // 金额
        token: Object<Metadata> // 代币类型
    }

   // 领取推荐费事件
    struct ClaimRefFeeEvent has drop, store {
        name: String, // 名称
        receiver: address, // 接收者地址
        token: Object<Metadata>, // 代币类型
        amount: u64 // 金额
    }

   // 获取合作伙伴费率分母
   // 返回值：合作伙伴费率分母
    public fun partner_fee_rate_denominator(): u64 {
        PARTNER_RATE_DENOMINATOR
    }

   // 在@eden_clmm账户中初始化合作伙伴
   // 参数：account - 初始化账户
    public fun initialize(account: &signer) {
        config::assert_initialize_authority(account);
        move_to(
            account,
            Partners {
                data: table::new<String, Partner>(),
                create_events: account::new_event_handle<CreateEvent>(account),
                update_fee_rate_events: account::new_event_handle<UpdateFeeRateEvent>(
                    account
                ),
                update_time_events: account::new_event_handle<UpdateTimeEvent>(account),
                transfer_receiver_events: account::new_event_handle<TransferReceiverEvent>(
                    account
                ),
                accept_receiver_events: account::new_event_handle<AcceptReceiverEvent>(
                    account
                ),
                receive_ref_fee_events: account::new_event_handle<ReceiveRefFeeEvent>(
                    account
                ),
                claim_ref_fee_events: account::new_event_handle<ClaimRefFeeEvent>(account)
            }
        )
    }

   // 创建合作伙伴，通过名称标识
   // 参数：
   //     - account: 协议权限账户
   //     - name: 合作伙伴名称
   //     - fee_rate: 费率
   //     - receiver: 用于接收代币的接收者地址
   //     - start_time: 开始时间
   //     - end_time: 结束时间
    public fun create_partner(
        account: &signer,
        name: String,
        fee_rate: u64,
        receiver: address,
        start_time: u64,
        end_time: u64
    ) acquires Partners {
        assert!(end_time > start_time, EINVALID_TIME);
        assert!(end_time > timestamp::now_seconds(), EINVALID_TIME);
        assert!(fee_rate < MAX_PARTNER_FEE_RATE, EINVALID_PARTNER_FEE_RATE);
        assert!(!name.is_empty(), EINVALID_PARTNER_NAME);

        config::assert_protocol_authority(account);
        let partners = borrow_global_mut<Partners>(@eden_clmm);
        assert!(!partners.data.contains(name), EPARTNER_ALREADY_EXISTED);
        let (partner_signer, signer_capability) =
            account::create_resource_account(account, *name.bytes());
        let partner_address = signer::address_of(&partner_signer);
        partners.data.add(
            name,
            Partner {
                metadata: PartnerMetadata {
                    receiver,
                    pending_receiver: DEFAULT_ADDRESS,
                    fee_rate,
                    start_time,
                    end_time,
                    partner_address
                },
                signer_capability
            }
        );
        event::emit_event<CreateEvent>(
            &mut partners.create_events,
            CreateEvent { partner_address, fee_rate, name, receiver, start_time, end_time }
        );
    }

   // 由协议权限更新合作伙伴费率
   // 参数：
   //     - account: 协议权限账户
   //     - name: 合作伙伴名称
   //     - new_fee_rate: 新费率
    public fun update_fee_rate(
        account: &signer, name: String, new_fee_rate: u64
    ) acquires Partners {
        assert!(new_fee_rate < MAX_PARTNER_FEE_RATE, EINVALID_PARTNER_FEE_RATE);

        config::assert_protocol_authority(account);
        let partners = borrow_global_mut<Partners>(@eden_clmm);
        assert!(partners.data.contains(name), EPARTNER_NOT_EXISTED);

        let partner = partners.data.borrow_mut(name);
        let old_fee_rate = partner.metadata.fee_rate;
        partner.metadata.fee_rate = new_fee_rate;
        event::emit_event(
            &mut partners.update_fee_rate_events,
            UpdateFeeRateEvent { name, old_fee_rate, new_fee_rate }
        );
    }

   // 由协议权限更新合作伙伴时间
   // 参数：
   //     - account: 协议权限账户
   //     - name: 合作伙伴名称
   //     - start_time: 开始时间
   //     - end_time: 结束时间
    public fun update_time(
        account: &signer,
        name: String,
        start_time: u64,
        end_time: u64
    ) acquires Partners {
        assert!(end_time > start_time, EINVALID_TIME);
        assert!(end_time > timestamp::now_seconds(), EINVALID_TIME);

        config::assert_protocol_authority(account);

        let partners = borrow_global_mut<Partners>(@eden_clmm);
        assert!(partners.data.contains(name), EPARTNER_NOT_EXISTED);
        let partner = partners.data.borrow_mut(name);
        partner.metadata.start_time = start_time;
        partner.metadata.end_time = end_time;
        event::emit_event(
            &mut partners.update_time_events,
            UpdateTimeEvent { name, start_time, end_time }
        );
    }

   // 转移接收权限
   // 参数：
   //     - account: 当前接收者账户
   //     - name: 合作伙伴名称
   //     - new_receiver: 新接收者地址
    public fun transfer_receiver(
        account: &signer, name: String, new_receiver: address
    ) acquires Partners {
        let old_receiver_addr = signer::address_of(account);
        let partners = borrow_global_mut<Partners>(@eden_clmm);
        assert!(partners.data.contains(name), EPARTNER_NOT_EXISTED);
        let partner = partners.data.borrow_mut(name);
        assert!(old_receiver_addr == partner.metadata.receiver, EINVALID_RECEIVER);
        partner.metadata.pending_receiver = new_receiver;
        event::emit_event(
            &mut partners.transfer_receiver_events,
            TransferReceiverEvent {
                name,
                old_receiver: partner.metadata.receiver,
                new_receiver
            }
        )
    }

   // 接受合作伙伴接收者
   // 参数：
   //     - account: 新接收者账户
   //     - name: 合作伙伴名称
    public fun accept_receiver(account: &signer, name: String) acquires Partners {
        let receiver_addr = signer::address_of(account);
        let partners = borrow_global_mut<Partners>(@eden_clmm);
        assert!(partners.data.contains(name), EPARTNER_NOT_EXISTED);
        let partner = partners.data.borrow_mut(name);
        assert!(receiver_addr == partner.metadata.pending_receiver, EINVALID_RECEIVER);
        partner.metadata.receiver = receiver_addr;
        partner.metadata.pending_receiver = DEFAULT_ADDRESS;
        event::emit_event(
            &mut partners.accept_receiver_events,
            AcceptReceiverEvent { name, receiver: receiver_addr }
        )
    }

   // 通过名称获取合作伙伴费率
   // 参数：
   //     - name: 合作伙伴名称
   // 返回值：
   //     - u64: 推荐费率
    public fun get_ref_fee_rate(name: String): u64 acquires Partners {
        let partners = &borrow_global<Partners>(@eden_clmm).data;
        if (!partners.contains(name)) {
            return 0
        };
        let partner = partners.borrow(name);
        let current_time = timestamp::now_seconds();
        if (partner.metadata.start_time > current_time
            || partner.metadata.end_time <= current_time) {
            return 0
        };
        partner.metadata.fee_rate
    }

   // 直接从交换中接收代币
   // 参数：
   //     - name: 合作伙伴名称
   //     - receive_asset: 要转移到合作伙伴的代币资源
    public fun receive_ref_fee(name: String, receive_asset: FungibleAsset) acquires Partners {
        let partners = borrow_global_mut<Partners>(@eden_clmm);
        assert!(partners.data.contains(name), EPARTNER_NOT_EXISTED);

        let partner = partners.data.borrow(name);

        // 将推荐费发送到合作伙伴账户
        let token = fungible_asset::asset_metadata(&receive_asset);
        let amount = fungible_asset::amount(&receive_asset);
        primary_fungible_store::deposit(partner.metadata.partner_address, receive_asset);

        event::emit_event(
            &mut partners.receive_ref_fee_events,
            ReceiveRefFeeEvent {
                name,
                amount,
                token
            }
        )
    }

   // 为合作伙伴领取合作伙伴账户的推荐费
   // 参数：
   //     - account: 接收者账户
   //     - name: 合作伙伴名称
    public fun claim_ref_fee(account: &signer, name: String, token: Object<Metadata>) acquires Partners {
        let partners = borrow_global_mut<Partners>(@eden_clmm);
        assert!(partners.data.contains(name), EPARTNER_NOT_EXISTED);

        let partner = partners.data.borrow(name);
        assert!(signer::address_of(account) == partner.metadata.receiver, EINVALID_RECEIVER);
        
        // 使用FungibleAsset从合作伙伴账户提取所有余额
        let partner_account = account::create_signer_with_capability(&partner.signer_capability);
        let fee_balance = primary_fungible_store::balance(signer::address_of(&partner_account), token);
        let ref_fee = primary_fungible_store::withdraw(&partner_account, token, fee_balance);

        // 将推荐费发送到接收者账户
        primary_fungible_store::deposit(partner.metadata.receiver, ref_fee);

        event::emit_event(
            &mut partners.claim_ref_fee_events,
            ClaimRefFeeEvent {
                name,
                receiver: partner.metadata.receiver,
                token,
                amount: fee_balance
            }
        )
    }
}
