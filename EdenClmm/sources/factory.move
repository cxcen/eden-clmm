/// 池子工厂模块
/// 负责创建和管理CLMM流动性池，类似于Uniswap V3的工厂合约
/// 每个池子由两种代币类型和tick间距唯一标识
module eden_clmm::factory {
    use std::bcs;
    use std::signer;
    use std::string::{Self, String};
    use std::option;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::Object;
    use eden_clmm::tick_math;
    use eden_clmm::utils;
    use eden_clmm::pool;
    use eden_clmm::config;
    use eden_clmm::fee_tier;
    use eden_clmm::partner;

    // 常量定义
    const POOL_OWNER_SEED: vector<u8> = b"EdenPoolOwner";
    // 池子所有者种子
    const COLLECTION_DESCRIPTION: vector<u8> = b"Eden Liquidity Position";
    // 收藏描述
    const POOL_DEFAULT_URI: vector<u8> = b"https://edbz27ws6curuggjavd2ojwm4td2se5x53elw2rbo3rwwnshkukq.arweave.net/IMOdftLwqRoYyQVHpybM5MepE7fuyLtqIXbjazZHVRU"; // 池子默认URI

    // 错误代码
    const EPOOL_ALREADY_INITIALIZED: u64 = 1;
    // 池子已初始化
    const EINVALID_SQRTPRICE: u64 = 2; // 无效的sqrt价格

    // 池子所有者，支持任何人创建池子，存储资源账户签名能力
    struct PoolOwner has key {
        // 签名能力
        signer_capability: account::SignerCapability
    }

    // 池子ID，用于唯一标识池子
    struct PoolId has store, copy, drop {
        // 代币A类型
        token_a: Object<Metadata>,
        // 代币B类型
        token_b: Object<Metadata>,
        // tick间距
        tick_spacing: u64
    }

    // 存储池子元数据信息在部署的(@eden_clmm)账户中
    struct Pools has key {
        // 池子ID到地址的映射
        data: SimpleMap<PoolId, address>,
        // 池子索引
        index: u64
    }

    // 创建池子事件
    #[event]
    struct CreatePoolEvent has drop, store {
        // 创建者地址
        creator: address,
        // 池子地址
        pool_address: address,
        // 位置收藏名称
        position_collection_name: String,
        // 代币A类型
        token_a: Object<Metadata>,
        // 代币B类型
        token_b: Object<Metadata>,
        // tick间距
        tick_spacing: u64
    }

    // 模块初始化函数
    // 参数：account - 部署账户
    fun init_module(account: &signer) {
        move_to(
            account,
            Pools {
                data: simple_map::create<PoolId, address>(),
                index: 0
            }
        );

        let (_, signer_cap) = account::create_resource_account(account, POOL_OWNER_SEED);
        move_to(account, PoolOwner { signer_capability: signer_cap });
        config::initialize(account);
        fee_tier::initialize(account);
        partner::initialize(account);
    }

    // 创建流动性池
    // 参数：
    //     - account: 创建者账户
    //     - tick_spacing: tick间距
    //     - initialize_price: 初始价格
    //     - uri: 位置NFT的URI
    // 返回值：池子地址
    public fun create_pool(
        account: &signer,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        tick_spacing: u64,
        initialize_price: u128,
        uri: String
    ): address acquires PoolOwner, Pools {
        config::assert_pool_create_authority(account);

        let uri =
            if (uri.length() == 0 || !config::allow_set_position_nft_uri(account)) {
                string::utf8(POOL_DEFAULT_URI)
            } else { uri };

        assert!(
            initialize_price >= tick_math::min_sqrt_price() && initialize_price <= tick_math::max_sqrt_price(),
            EINVALID_SQRTPRICE
        );

        // 创建池子账户
        let pool_id = new_pool_id(token_a, token_b, tick_spacing);
        let pool_owner = borrow_global<PoolOwner>(@eden_clmm);
        let pool_owner_signer =
            account::create_signer_with_capability(&pool_owner.signer_capability);

        let pool_seed = new_pool_seed(token_a, token_b, tick_spacing);
        let pool_seed = bcs::to_bytes<PoolId>(&pool_seed);
        let (pool_signer, signer_cap) =
            account::create_resource_account(&pool_owner_signer, pool_seed);
        let pool_address = signer::address_of(&pool_signer);

        let pools = borrow_global_mut<Pools>(@eden_clmm);
        pools.index += 1;
        assert!(!pools.data.contains_key::<PoolId, address>(&pool_id), EPOOL_ALREADY_INITIALIZED);
        pools.data.add::<PoolId, address>(pool_id, pool_address);

        // 初始化池子元数据
        let position_collection_name =
            pool::new(
                &pool_signer,
                token_a,
                token_b,
                tick_spacing,
                initialize_price,
                pools.index,
                uri,
                signer_cap
            );

        event::emit(
            CreatePoolEvent {
                token_a,
                token_b,
                tick_spacing,
                creator: signer::address_of(account),
                pool_address,
                position_collection_name
            }
        );
        pool_address
    }

    // 获取池子地址
    // 参数：tick_spacing - tick间距
    // 返回值：池子地址（如果存在）
    public fun get_pool(
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        tick_spacing: u64
    ): option::Option<address> acquires Pools {
        let pools = borrow_global<Pools>(@eden_clmm);
        let pool_id = new_pool_id(token_a, token_b, tick_spacing);
        if (pools.data.contains_key(&pool_id)) {
            return option::some(*pools.data.borrow(&pool_id))
        };
        option::none<address>()
    }

    // 创建新的池子ID
    // 参数：tick_spacing - tick间距
    // 返回值：池子ID
    fun new_pool_id(
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        tick_spacing: u64
    ): PoolId {
        PoolId {
            token_a,
            token_b,
            tick_spacing
        }
    }

    // 创建新的池子种子（确保代币类型排序）
    // 参数：tick_spacing - tick间距
    // 返回值：池子ID（代币类型已排序）
    fun new_pool_seed(
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        tick_spacing: u64
    ): PoolId {
        if (utils::compare_coin(token_a, token_b).is_smaller_than()) {
            PoolId {
                token_a,
                token_b,
                tick_spacing
            }
        } else {
            PoolId {
                token_a: token_b,
                token_b: token_a,
                tick_spacing
            }
        }
    }
}
