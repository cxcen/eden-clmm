/// 集中流动性做市商（CLMM）池子模块
/// 
/// 这是整个Eden DEX的核心模块，实现了类似Uniswap V3的集中流动性机制。
/// 主要功能包括：
/// 1. 流动性池的创建和管理
/// 2. 集中流动性位置的开启、关闭和管理
/// 3. 代币交换（swap）的核心逻辑
/// 4. 费用收取和分配机制
/// 5. 流动性挖矿奖励系统
/// 6. 协议费用管理
/// 7. 价格预言机功能
/// 8. 位置NFT化管理
module eden_clmm::pool {
    use std::string::{Self, String};               // 字符串操作
    use std::vector;                               // 动态数组操作
    use std::signer;                               // 签名者操作
    use std::bit_vector::{Self, BitVector};        // 位向量，用于tick索引管理
    use std::option::{Self, Option};               // 可选值类型
    use aptos_std::table::{Self, Table};           // 哈希表，用于存储tick和position数据
    use aptos_token::token;                        // NFT代币标准，用于位置NFT
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, FungibleStore}; // 可替代资产操作
    use aptos_framework::object::Object;                          // 对象操作
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::primary_fungible_store;                  // 账户操作
    use aptos_framework::timestamp;                // 时间戳操作
    use integer_mate::i64::{Self, I64};            // 64位有符号整数，用于tick索引
    use integer_mate::i128::{Self, I128, is_neg};  // 128位有符号整数，用于流动性变化
    use integer_mate::math_u128;                   // 128位无符号整数数学运算
    use integer_mate::math_u64;                    // 64位无符号整数数学运算
    use integer_mate::full_math_u64;               // 64位高精度数学运算
    use integer_mate::full_math_u128;              // 128位高精度数学运算
    use eden_clmm::config;                        // 协议配置管理
    use eden_clmm::partner;                       // 合作伙伴费用分成
    use eden_clmm::tick_math;                     // tick和价格转换数学库
    use eden_clmm::clmm_math;                     // 集中流动性数学计算
    use eden_clmm::fee_tier;                      // 费用等级管理
    use eden_clmm::tick_math::{min_sqrt_price, max_sqrt_price, is_valid_index}; // tick数学函数
    use eden_clmm::position_nft;                  // 位置NFT管理

    friend eden_clmm::factory;                    // 友元模块：工厂合约可以调用本模块的内部函数

   // tick索引位向量的长度
   // 用于管理tick的激活状态，每个池子可以有1000个tick索引组
    const TICK_INDEXES_LENGTH: u64 = 1000;

   // 协议费率的分母（费率=协议费率/10000）
   // 例如：协议费率为30表示0.3%的费率
    const PROTOCOL_FEE_DENOMNINATOR: u64 = 10000;

   // 每个池子支持的奖励器数量
   // 最多支持3个不同的奖励代币同时进行流动性挖矿
    const REWARDER_NUM: u64 = 3;

   // 一天的秒数，用于奖励计算
    const DAYS_IN_SECONDS: u128 = 24 * 60 * 60;

   // 默认地址（零地址）
    const DEFAULT_ADDRESS: address = @0x0;

   // 位置NFT集合的描述
    const COLLECTION_DESCRIPTION: vector<u8> = b"Eden Liquidity Position";

   // 池子位置NFT的默认URI
    const POOL_DEFAULT_URI: vector<u8> = b"https://edbz27ws6curuggjavd2ojwm4td2se5x53elw2rbo3rwwnshkukq.arweave.net/IMOdftLwqRoYyQVHpybM5MepE7fuyLtqIXbjazZHVRU";

   // 错误码定义
   // 这些错误码覆盖了集中流动性操作中可能出现的各种错误情况

    const EINVALID_TICK: u64 = 1;
    // 无效的tick索引
    const ETICK_ALREADY_INTIIALIZE: u64 = 2;
    // tick已经初始化
    const ETICK_SPACING_IS_ZERO: u64 = 3;
    // tick间距为零
    const EAMOUNT_IN_ABOVE_MAX_LIMIT: u64 = 4;
    // 输入数量超过最大限制
    const EAMOUNT_OUT_BELOW_MIN_LIMIT: u64 = 5;
    // 输出数量低于最小限制
    const EAMOUNT_INCORRECT: u64 = 6;
    // 数量不正确
    const ELIQUIDITY_OVERFLOW: u64 = 7;
    // 流动性溢出
    const ELIQUIDITY_UNDERFLOW: u64 = 8;
    // 流动性下溢
    const ETICK_INDEXES_NOT_SET: u64 = 9;
    // tick索引未设置
    const ETICK_NOT_FOUND: u64 = 10;
    // tick未找到
    const ELIQUIDITY_IS_ZERO: u64 = 11;
    // 流动性为零
    const ENOT_ENOUGH_LIQUIDITY: u64 = 12;
    // 流动性不足
    const EREMAINER_AMOUNT_UNDERFLOW: u64 = 13;
    // 剩余数量下溢
    const ESWAP_AMOUNT_IN_OVERFLOW: u64 = 14;
    // 交换输入数量溢出
    const ESWAP_AMOUNT_OUT_OVERFLOW: u64 = 15;
    // 交换输出数量溢出
    const ESWAP_FEE_AMOUNT_OVERFLOW: u64 = 16;
    // 交换费用数量溢出
    const EINVALID_FEE_RATE: u64 = 17;
    // 无效的费率
    const EINVALID_FIXED_TOKEN_TYPE: u64 = 18;
    // 无效的固定代币类型
    const EPOOL_NOT_EXISTS: u64 = 19;
    // 池子不存在
    const ESWAP_AMOUNT_INCORRECT: u64 = 20;
    // 交换数量不正确
    const EINVALID_PARTNER: u64 = 21;
    // 无效的合作伙伴
    const EWRONG_SQRT_PRICE_LIMIT: u64 = 22;
    // 错误的价格平方根限制
    const EINVALID_REWARD_INDEX: u64 = 23;
    // 无效的奖励索引
    const EREWARD_AMOUNT_INSUFFICIENT: u64 = 24;
    // 奖励数量不足
    const EREWARD_NOT_MATCH_WITH_INDEX: u64 = 25;
    // 奖励与索引不匹配
    const EREWARD_AUTH_ERROR: u64 = 26;
    // 奖励权限错误
    const EINVALID_TIME: u64 = 27;
    // 无效的时间
    const EPOSITION_OWNER_ERROR: u64 = 28;
    // 位置所有者错误
    const EPOSITION_NOT_EXIST: u64 = 29;
    // 位置不存在
    const EIS_NOT_VALID_TICK: u64 = 30;
    // 不是有效的tick
    const EPOOL_ADDRESS_ERROR: u64 = 31;
    // 池子地址错误
    const EPOOL_IS_PAUDED: u64 = 32;
    // 池子已暂停
    const EPOOL_LIQUIDITY_IS_NOT_ZERO: u64 = 33;
    // 池子流动性不为零
    const EREWARDER_OWNED_OVERFLOW: u64 = 34;
    // 奖励器欠款溢出
    const EFEE_OWNED_OVERFLOW: u64 = 35;
    // 费用欠款溢出
    const EINVALID_DELTA_LIQUIDITY: u64 = 36;
    // 无效的流动性变化量
    const ESAME_COIN_TYPE: u64 = 37;
    // 相同的代币类型
    const EINVALID_SQRT_PRICE: u64 = 38;
    // 无效的价格平方根
    const EFUNC_DISABLED: u64 = 39;
    // 功能已禁用
    const ENOT_HAS_PRIVILEGE: u64 = 40;
    // 没有权限
    const EINVALID_POOL_URI: u64 = 41;               // 无效的池子URI

   // 集中流动性池子的核心数据结构
   //
   // 这是整个DEX的核心数据结构，包含了一个交易对的所有状态信息：
   // - 流动性管理：当前流动性、tick状态、位置信息
   // - 价格管理：当前价格、tick索引
   // - 费用管理：全局费用增长、协议费用
   // - 奖励管理：流动性挖矿奖励
   // - 事件管理：各种操作的事件记录
    struct Pool has key {
       // 池子索引，用于标识不同的池子
        index: u64,

       // 池子位置代币NFT集合名称
        collection_name: String,

       // 池子中的代币A余额
        store_a: Object<FungibleStore>,

       // 池子中的代币B余额
        store_b: Object<FungibleStore>,

       // 代币A的元数据对象
        metadata_a: Object<Metadata>,

       // 代币B的元数据对象
        metadata_b: Object<Metadata>,

       // tick间距，决定了价格粒度
       // 间距越小，价格精度越高，但gas消耗也越大
        tick_spacing: u64,

       // 交易费率的分子，分母为1_000_000
       // 例如：fee_rate=3000表示0.3%的交易费
        fee_rate: u64,

       // 当前tick索引处的总流动性
       // 这是当前价格范围内所有位置的流动性总和
        liquidity: u128,

       // 当前价格的平方根（Q64.64格式）
       // 使用平方根价格可以避免精度损失和溢出问题
        current_sqrt_price: u128,

       // 当前tick索引
       // tick索引决定了当前价格，每个tick代表一个价格点
        current_tick_index: I64,

       // 代币A的全局费用增长率（Q64.64格式）
       // 用于计算每个位置应得的费用分成
        fee_growth_global_a: u128,

       // 代币B的全局费用增长率（Q64.64格式）
        fee_growth_global_b: u128,

       // 协议应收的代币A费用
       // 这是从交易费中分配给协议的部分
        fee_protocol_coin_a: u64,

       // 协议应收的代币B费用
        fee_protocol_coin_b: u64,

       // tick索引位向量表
       // 用于快速查找哪些tick被激活（有流动性）
        tick_indexes: Table<u64, BitVector>,

       // tick数据表
       // 存储每个tick的详细信息：流动性、费用增长等
        ticks: Table<I64, Tick>,

       // 奖励器信息数组
       // 支持最多3个不同代币的流动性挖矿奖励
        rewarder_infos: vector<Rewarder>,

       // 奖励器最后更新时间
       // 用于计算奖励分配
        rewarder_last_updated_time: u64,

       // 位置信息表
       // 存储每个流动性位置的详细信息
        positions: Table<u64, Position>,

       // 位置计数器
       // 用于生成新位置的唯一ID
        position_index: u64,

       // 池子是否暂停
       // 暂停时不能进行交易和流动性操作
        is_pause: bool,

       // 位置NFT的URI
       // 用于NFT元数据展示
        uri: String,

       // 池子账户的签名能力
       // 用于池子代表用户执行操作
        signer_cap: account::SignerCapability,
    }

   // 集中流动性池子的tick数据结构
   //
   // Tick是集中流动性的核心概念，每个tick代表一个特定的价格点。
   // 流动性提供者在两个tick之间提供流动性，当价格跨越tick时，
   // 该tick的流动性会被激活或停用。
    struct Tick has copy, drop, store {
       // tick索引，对应特定的价格点
        index: I64,

       // 该tick对应的价格平方根
       // 用于快速计算价格相关的数学运算
        sqrt_price: u128,

       // 流动性净变化量（有符号）
       // 正值表示价格上升时流动性增加，负值表示流动性减少
        liquidity_net: I128,

       // 流动性总量（无符号）
       // 表示有多少流动性位置以此tick为边界
        liquidity_gross: u128,

       // 代币A在该tick外部的费用增长率
       // 用于计算跨越该tick的位置的费用分成
        fee_growth_outside_a: u128,

       // 代币B在该tick外部的费用增长率
        fee_growth_outside_b: u128,

       // 各个奖励器在该tick外部的增长率
       // 用于计算流动性挖矿奖励的分配
        rewarders_growth_outside: vector<u128>,
    }

   // 集中流动性位置数据结构
   //
   // Position代表一个流动性提供者在特定价格区间内的流动性位置。
   // 每个位置都有明确的价格边界（tick_lower到tick_upper），
   // 只有当当前价格在这个区间内时，该位置的流动性才会被激活用于交易。
    struct Position has copy, drop, store {
       // 该位置所属的池子地址
        pool: address,

       // 位置的唯一标识符
        index: u64,

       // 该位置提供的流动性数量
       // 流动性数量决定了该位置在价格区间内能够支持的交易量
        liquidity: u128,

       // 位置的下边界tick索引
       // 当价格低于此tick时，该位置的流动性不会被使用
        tick_lower_index: I64,

       // 位置的上边界tick索引
       // 当价格高于此tick时，该位置的流动性不会被使用
        tick_upper_index: I64,

       // 该位置内部代币A的费用增长率
       // 用于计算该位置应得的代币A费用分成
        fee_growth_inside_a: u128,

       // 该位置累计应得的代币A费用
       // 这是已经计算但尚未提取的费用
        fee_owed_a: u64,

       // 该位置内部代币B的费用增长率
       // 用于计算该位置应得的代币B费用分成
        fee_growth_inside_b: u128,

       // 该位置累计应得的代币B费用
        fee_owed_b: u64,

       // 该位置的奖励器信息数组
       // 记录每个奖励器对该位置的奖励分配情况
        rewarder_infos: vector<PositionRewarder>,
    }

   // 流动性挖矿奖励器数据结构
   //
   // Rewarder负责管理流动性挖矿的奖励分配，每个奖励器对应一种奖励代币。
   // 奖励器按照流动性提供者的贡献比例分配奖励，激励用户提供流动性。
    struct Rewarder has copy, drop, store {
       // 奖励代币的类型信息
       // 用于识别奖励使用的是哪种代币
        token: Object<Metadata>,

       // 奖励器的管理权限地址
       // 只有该地址可以修改奖励器的参数
        authority: address,

       // 待转移的权限地址
       // 用于权限转移的两步验证流程
        pending_authority: address,

       // 每秒钟的奖励发放数量
       // 控制奖励的发放速度
        emissions_per_second: u128,

       // 全局奖励增长率
       // 用于计算每个位置应得的奖励分成
        growth_global: u128
    }

   // 位置奖励器数据结构
   //
   // 记录每个位置在特定奖励器中的奖励分配情况，
   // 用于计算该位置应得的奖励数量。
    struct PositionRewarder has drop, copy, store {
       // 该位置内部的奖励增长率
       // 用于计算该位置应得的奖励分成
        growth_inside: u128,

       // 该位置累计应得的奖励数量
       // 这是已经计算但尚未提取的奖励
        amount_owed: u64,
    }

   // 闪电交换收据
   //
   // 闪电交换是DEX的核心功能，允许用户在同一笔交易中先获得代币，再支付相应的费用。
   // 这个收据记录了闪电交换的关键信息，用于确保交易的原子性和安全性。
   //
   // 在Move语言中，无法传递回调数据和进行动态调用，但可以使用资源来实现这一目的。
   // 为了确保执行在单个交易中完成，闪电交换函数必须返回一个不能被复制、
   // 不能被保存、不能被丢弃或克隆的资源。
    struct FlashSwapReceipt {
       // 进行闪电交换的池子地址
        pool_address: address,

       // 交换方向：true表示A换B，false表示B换A
        a2b: bool,

       // 合作伙伴名称，用于费用分成
        partner_name: String,

       // 需要支付的代币数量
        pay_amount: u64,

       // 合作伙伴推荐费用数量
        ref_fee_amount: u64
    }

   // 添加流动性收据
   //
   // 用于添加流动性操作的两阶段提交，确保用户支付正确的代币数量。
    struct AddLiquidityReceipt {
       // 操作的池子地址
        pool_address: address,

       // 需要支付的代币A数量
        amount_a: u64,

       // 需要支付的代币B数量
        amount_b: u64
    }

   // 交换结果数据结构
   //
   // 记录一次交换操作的完整结果信息。
    struct SwapResult has copy, drop {
       // 实际输入的代币数量
        amount_in: u64,

       // 实际输出的代币数量
        amount_out: u64,

       // 支付的交易费用
        fee_amount: u64,

       // 合作伙伴推荐费用
        ref_fee_amount: u64,
    }

   // 计算出的交换结果数据结构
   //
   // 包含交换操作的详细计算结果，用于预估和验证。
    struct CalculatedSwapResult has copy, drop, store {
       // 计算的输入代币数量
        amount_in: u64,

       // 计算的输出代币数量
        amount_out: u64,

       // 计算的交易费用
        fee_amount: u64,

       // 使用的费率
        fee_rate: u64,

       // 交换后的价格平方根
        after_sqrt_price: u128,

       // 是否超出了价格限制
        is_exceed: bool,

       // 每一步的交换结果详情
        step_results: vector<SwapStepResult>
    }

   // 单步交换结果数据结构
   //
   // 记录交换过程中每一步的详细信息，用于调试和审计。
    struct SwapStepResult has copy, drop, store {
       // 当前步骤开始时的价格平方根
        current_sqrt_price: u128,

       // 目标价格平方根
        target_sqrt_price: u128,

       // 当前步骤的流动性
        current_liquidity: u128,

       // 该步骤的输入数量
        amount_in: u64,

       // 该步骤的输出数量
        amount_out: u64,

       // 该步骤的费用
        fee_amount: u64,

       // 剩余未处理的数量
        remainer_amount: u64
    }

    // 事件结构体定义
    // ============================================================================================================
    // 这些事件结构体用于记录池子中发生的各种重要操作，便于前端监听和数据分析

   // 开启位置事件
   // 当用户创建新的流动性位置时触发
    #[event]
    struct OpenPositionEvent has drop, store {
       // 用户地址
        user: address,

       // 池子地址
        pool: address,

       // 位置的下边界tick
        tick_lower: I64,

       // 位置的上边界tick
        tick_upper: I64,

       // 位置索引
        index: u64
    }

   // 关闭位置事件
   // 当用户关闭流动性位置时触发
    #[event]
    struct ClosePositionEvent has drop, store {
       // 用户地址
        user: address,

       // 池子地址
        pool: address,

       // 位置索引
        index: u64
    }

   // 添加流动性事件
   // 当用户向位置添加流动性时触发
    #[event]
    struct AddLiquidityEvent has drop, store {
       // 池子地址
        pool_address: address,

       // 位置的下边界tick
        tick_lower: I64,

       // 位置的上边界tick
        tick_upper: I64,

       // 添加的流动性数量
        liquidity: u128,

       // 添加的代币A数量
        amount_a: u64,

       // 添加的代币B数量
        amount_b: u64,

       // 位置索引
        index: u64
    }

   // 移除流动性事件
   // 当用户从位置移除流动性时触发
    #[event]
    struct RemoveLiquidityEvent has drop, store {
       // 池子地址
        pool_address: address,

       // 位置的下边界tick
        tick_lower: I64,

       // 位置的上边界tick
        tick_upper: I64,

       // 移除的流动性数量
        liquidity: u128,

       // 移除的代币A数量
        amount_a: u64,

       // 移除的代币B数量
        amount_b: u64,

       // 位置索引
        index: u64
    }

   // 交换事件
   // 当用户进行代币交换时触发
    #[event]
    struct SwapEvent has drop, store {
       // 交换方向：true为A换B，false为B换A
        atob: bool,

       // 池子地址
        pool_address: address,

       // 交换发起者地址
        swap_from: address,

       // 合作伙伴名称
        partner: String,

       // 输入代币数量
        amount_in: u64,

       // 输出代币数量
        amount_out: u64,

       // 合作伙伴推荐费用
        ref_amount: u64,

       // 交易费用
        fee_amount: u64,

       // 池子中代币A的余额
        vault_a_amount: u64,

       // 池子中代币B的余额
        vault_b_amount: u64,
    }

   // 收集协议费用事件
   // 当协议管理员收集协议费用时触发
    #[event]
    struct CollectProtocolFeeEvent has drop, store {
       // 池子地址
        pool_address: address,

       // 收集的代币A费用
        amount_a: u64,

       // 收集的代币B费用
        amount_b: u64
    }

   // 收集费用事件
   // 当用户收集位置费用时触发
    #[event]
    struct CollectFeeEvent has drop, store {
       // 位置索引
        index: u64,

       // 用户地址
        user: address,

       // 池子地址
        pool_address: address,

       // 收集的代币A费用
        amount_a: u64,

       // 收集的代币B费用
        amount_b: u64
    }

   // 更新费率事件
   // 当协议管理员更新池子费率时触发
    #[event]
    struct UpdateFeeRateEvent has drop, store {
       // 池子地址
        pool_address: address,

       // 旧费率
        old_fee_rate: u64,

       // 新费率
        new_fee_rate: u64
    }

   // 更新奖励发放事件
   // 当奖励器管理员更新奖励发放速率时触发
    #[event]
    struct UpdateEmissionEvent has drop, store {
       // 池子地址
        pool_address: address,

       // 奖励器索引
        index: u8,

       // 每秒发放数量
        emissions_per_second: u128,
    }

   // 转移奖励权限事件
   // 当奖励器权限被转移时触发
    #[event]
    struct TransferRewardAuthEvent has drop, store {
       // 池子地址
        pool_address: address,

       // 奖励器索引
        index: u8,

       // 旧权限地址
        old_authority: address,

       // 新权限地址
        new_authority: address
    }

   // 接受奖励权限事件
   // 当新权限地址接受奖励器权限时触发
    #[event]
    struct AcceptRewardAuthEvent has drop, store {
       // 池子地址
        pool_address: address,

       // 奖励器索引
        index: u8,

       // 权限地址
        authority: address
    }

   // 收集奖励事件
   // 当用户收集流动性挖矿奖励时触发
    #[event]
    struct CollectRewardEvent has drop, store {
       // 位置索引
        pos_index: u64,

       // 用户地址
        user: address,

       // 池子地址
        pool_address: address,

       // 收集的奖励数量
        amount: u64,

       // 奖励器索引
        index: u8
    }

    // 公共函数
    // ============================================================================================================

   // 初始化一个新的集中流动性池子
   //
   // 这是创建新交易对池子的核心函数，只能由工厂合约调用。
   // 它会设置池子的基本参数，创建NFT集合，并初始化所有必要的数据结构。
   //
   // 参数：
   //     - account: 池子资源账户（用于存储池子数据）
   //     - tick_spacing: tick间距，决定价格精度和gas消耗
   //     - init_sqrt_price: 初始价格的平方根
   //     - index: 池子索引，用于标识不同的池子
   //     - uri: 位置NFT集合的URI
   //     - signer_cap: 池子资源账户的签名能力
   //
   // 返回：
   //     - pool_name: 池子的位置NFT集合名称
    ///
    public(friend) fun new(
        account: &signer,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        tick_spacing: u64,
        init_sqrt_price: u128,
        index: u64,
        uri: String,
        signer_cap: account::SignerCapability,
    ): String {
        // 确保两个代币类型不同
        assert!(token_a != token_b, ESAME_COIN_TYPE);

        // 根据tick间距获取相应的费率
        let fee_rate = fee_tier::get_fee_rate(tick_spacing);

        // 创建池子的位置NFT集合
        let collection_name = position_nft::create_collection(
            account,
            tick_spacing,
            string::utf8(COLLECTION_DESCRIPTION),
            uri,
            token_a,
            token_b
        );

        let pool_address = signer::address_of(account);
        // 创建池子资源并存储到账户中
        move_to(account, Pool {
            store_a: primary_fungible_store::create_primary_store(pool_address, token_a),
            store_b: primary_fungible_store::create_primary_store(pool_address, token_b),
            metadata_a: token_a,
            metadata_b: token_b,
            tick_spacing,
            fee_rate,
            liquidity: 0,
            current_sqrt_price: init_sqrt_price,
            current_tick_index: tick_math::get_tick_at_sqrt_price(init_sqrt_price),
            fee_growth_global_a: 0,
            fee_growth_global_b: 0,
            fee_protocol_coin_a: 0,
            fee_protocol_coin_b: 0,
            tick_indexes: table::new(),
            ticks: table::new(),
            rewarder_infos: vector::empty(),
            rewarder_last_updated_time: 0,
            collection_name,
            index,
            positions: table::new(),
            position_index: 1,
            is_pause: false,
            uri,
            signer_cap,
        });

        // 为池子创建一个代币来保留集合数据，因为如果集合供应量为0，0x3::token会删除集合数据
        token::initialize_token_store(account);
        position_nft::mint(
            account,
            account,
            index,
            0,
            uri,
            collection_name
        );

        collection_name
    }

   // 重置池子的初始价格（如果池子从未添加过流动性）
   //
   // 这个函数已被禁用，使用reset_init_price_v2代替
   //
   // 参数：
   //     - pool_address: 池子账户地址
   //     - new_initialize_price: 池子的新初始价格平方根
    public fun reset_init_price(_pool_address: address, _new_initialize_price: u128) {
        abort EFUNC_DISABLED
        //let pool = borrow_global_mut<Pool>(pool_address);
        //assert!(pool.position_index == 1, EPOOL_LIQUIDITY_IS_NOT_ZERO);
        //pool.current_sqrt_price = new_initialize_price;
        //pool.current_tick_index = tick_math::get_tick_at_sqrt_price(new_initialize_price);
    }

   // 重置池子的初始价格（版本2）
   //
   // 只有在池子从未添加过任何流动性的情况下才能重置初始价格。
   // 这个功能用于在池子创建后但添加流动性前修正价格设置错误。
   //
   // 参数：
   //     - account: 有权限重置价格的账户
   //     - pool_address: 池子地址
   //     - new_initialize_price: 新的初始价格平方根
    public fun reset_init_price_v2(
        account: &signer,
        pool_address: address,
        new_initialize_price: u128
    ) acquires Pool {
        // 验证账户有重置价格的权限
        config::assert_reset_init_price_authority(account);
        let pool = borrow_global_mut<Pool>(pool_address);

        // 确保新价格在有效范围内
        assert!(
            new_initialize_price > tick_math::get_sqrt_price_at_tick(tick_min(pool.tick_spacing)) &&
                new_initialize_price < tick_math::get_sqrt_price_at_tick(tick_max(pool.tick_spacing)),
            EINVALID_SQRT_PRICE
        );

        // 确保池子从未添加过流动性（position_index为1表示只有预留的初始位置）
        assert!(pool.position_index == 1, EPOOL_LIQUIDITY_IS_NOT_ZERO);
        pool.current_sqrt_price = new_initialize_price;
        pool.current_tick_index = tick_math::get_tick_at_sqrt_price(new_initialize_price);
    }

   // 暂停池子
   //
   // 暂停池子会阻止所有交易和流动性操作，用于紧急情况或维护。
   // 只有协议管理员可以暂停池子。
   //
   // 参数：
   //     - account: 协议权限签名者
   //     - pool_address: 池子账户地址
    public fun pause(
        account: &signer,
        pool_address: address
    ) acquires Pool {
        // 验证协议状态和权限
        config::assert_protocol_status();
        config::assert_protocol_authority(account);
        let pool = borrow_global_mut<Pool>(pool_address);
        pool.is_pause = true;
    }

   // 恢复池子
   //
   // 恢复被暂停的池子，使其可以正常进行交易和流动性操作。
   // 只有协议管理员可以恢复池子。
   //
   // 参数：
   //     - account: 协议权限签名者
   //     - pool_address: 池子账户地址
    public fun unpause(
        account: &signer,
        pool_address: address
    ) acquires Pool {
        // 验证协议状态和权限
        config::assert_protocol_status();
        config::assert_protocol_authority(account);
        let pool = borrow_global_mut<Pool>(pool_address);
        pool.is_pause = false;
    }

   // 更新池子费率
   //
   // 允许协议管理员动态调整池子的交易费率。
   // 费率变更会立即生效，影响后续的所有交易。
   //
   // 参数：
   //     - account: 协议权限签名者
   //     - pool_address: 池子地址
   //     - fee_rate: 新的费率（分子，分母为1,000,000）
    public fun update_fee_rate(
        account: &signer,
        pool_address: address,
        fee_rate: u64
    ) acquires Pool {
        // 验证费率不超过最大允许值
        if (fee_rate > fee_tier::max_fee_rate()) {
            abort EINVALID_FEE_RATE
        };

        // 验证协议权限
        config::assert_protocol_authority(account);

        let pool_info = borrow_global_mut<Pool>(pool_address);
        assert_status(pool_info);
        let old_fee_rate = pool_info.fee_rate;
        pool_info.fee_rate = fee_rate;

        // 发布费率更新事件
        event::emit(UpdateFeeRateEvent {
            pool_address,
            old_fee_rate,
            new_fee_rate: fee_rate
        })
    }

   // 开启新的流动性位置
   //
   // 创建一个新的集中流动性位置，指定价格区间。
   // 位置创建后会铸造对应的NFT作为所有权凭证。
   // 注意：此时位置还没有流动性，需要调用add_liquidity来添加。
   //
   // 参数：
   //     - account: 位置所有者
   //     - pool_address: 池子账户地址
   //     - tick_lower_index: 位置的下边界tick索引
   //     - tick_upper_index: 位置的上边界tick索引
   //
   // 返回：
   //     - position_index: 新创建位置的索引
    public fun open_position(
        account: &signer,
        pool_address: address,
        tick_lower_index: I64,
        tick_upper_index: I64,
    ): u64 acquires Pool {
        // 确保下边界tick小于上边界tick
        assert!(i64::lt(tick_lower_index, tick_upper_index), EIS_NOT_VALID_TICK);

        // 获取池子资源
        let pool_info = borrow_global_mut<Pool>(pool_address);
        assert_status(pool_info);

        // 检查tick范围的有效性
        assert!(is_valid_index(tick_lower_index, pool_info.tick_spacing), EIS_NOT_VALID_TICK);
        assert!(is_valid_index(tick_upper_index, pool_info.tick_spacing), EIS_NOT_VALID_TICK);

        // 将位置添加到池子中
        pool_info.positions.add(
            pool_info.position_index,
            new_empty_position(pool_address, tick_lower_index, tick_upper_index, pool_info.position_index)
        );

        // 铸造位置NFT
        let pool_signer = account::create_signer_with_capability(&pool_info.signer_cap);
        position_nft::mint(
            account,
            &pool_signer,
            pool_info.index,
            pool_info.position_index,
            pool_info.uri,
            pool_info.collection_name
        );

        // 发布开启位置事件
        event::emit(OpenPositionEvent {
            user: signer::address_of(account),
            pool: pool_address,
            tick_upper: tick_upper_index,
            tick_lower: tick_lower_index,
            index: pool_info.position_index
        });

        let position_index = pool_info.position_index;
        pool_info.position_index += 1;
        position_index
    }

   // 按流动性数量向位置添加流动性
   //
   // 这是添加流动性的基础方法之一，直接指定要添加的流动性数量。
   // 任何人都可以向任何位置添加流动性，请在调用前检查位置的所有权。
   //
   // 参数：
   //     - pool_address: 池子账户地址
   //     - liquidity: 要添加的流动性数量
   //     - position_index: 位置索引
   //
   // 返回：
   //     - receipt: 添加流动性收据（热土豆模式，必须立即处理）
    public fun add_liquidity(
        pool_address: address,
        liquidity: u128,
        position_index: u64
    ): AddLiquidityReceipt acquires Pool {
        // 确保流动性不为零
        assert!(liquidity != 0, ELIQUIDITY_IS_ZERO);
        add_liquidity_internal(
            pool_address,
            position_index,
            false,
            liquidity,
            0,
            false
        )
    }

   // 按固定代币数量向位置添加流动性
   //
   // 这是另一种添加流动性的方法，通过固定一种代币的数量来添加流动性。
   // 系统会自动计算需要的另一种代币数量以保持价格比例。
   // 任何人都可以向任何位置添加流动性，请在调用前检查位置的所有权。
   //
   // 参数：
   //     - pool_address: 池子账户地址
   //     - amount: 固定的代币数量
   //     - fix_amount_a: 如果为true，amount是代币A的数量；否则是代币B的数量
   //     - position_index: 位置索引
   //
   // 返回：
   //     - receipt: 添加流动性收据（热土豆模式，必须立即处理）
    public fun add_liquidity_fix_coin(
        pool_address: address,
        amount: u64,
        fix_amount_a: bool,
        position_index: u64
    ): AddLiquidityReceipt acquires Pool {
        // 确保数量大于零
        assert!(amount > 0, EAMOUNT_INCORRECT);
        add_liquidity_internal(
            pool_address,
            position_index,
            true,
            0,
            amount,
            fix_amount_a
        )
    }

   // 偿还代币以完成流动性添加
   //
   // 这是添加流动性操作的第二步，用户需要支付相应数量的代币。
   // 这种两步操作确保了原子性：要么完全成功，要么完全失败。
   //
   // 参数：
   //     - coin_a: 代币A
   //     - coin_b: 代币B
   //     - receipt: 添加流动性收据（热土豆模式）
    public fun repay_add_liquidity(
        asset_a: FungibleAsset,
        asset_b: FungibleAsset,
        receipt: AddLiquidityReceipt
    ) acquires Pool {
        let AddLiquidityReceipt {
            pool_address,
            amount_a,
            amount_b
        } = receipt;

        // 验证支付的代币数量与收据要求一致
        assert!(fungible_asset::amount(&asset_a) == amount_a, EAMOUNT_INCORRECT);
        assert!(fungible_asset::amount(&asset_b) == amount_b, EAMOUNT_INCORRECT);

        let pool = borrow_global_mut<Pool>(pool_address);

        // 将代币合并到池子中
        fungible_asset::deposit(pool.store_a, asset_a);
        fungible_asset::deposit(pool.store_b, asset_b);
    }

   // 从池子中移除流动性
   //
   // 从指定位置移除一定数量的流动性，并返回相应的代币。
   // 移除流动性时会同时更新位置的费用和奖励，确保用户能收到应得的收益。
   //
   // 参数：
   //     - account: 位置所有者
   //     - pool_address: 池子账户地址
   //     - liquidity: 要移除的流动性数量
   //     - position_index: 位置索引
   //
   // 返回：
   //     - coin_a: 退还给用户的代币A
   //     - coin_b: 退还给用户的代币B
    public fun remove_liquidity(
        account: &signer,
        pool_address: address,
        liquidity: u128,
        position_index: u64
    ): (FungibleAsset, FungibleAsset) acquires Pool {
        // 确保移除的流动性不为零
        assert!(liquidity != 0, ELIQUIDITY_IS_ZERO);
        check_position_authority(account, pool_address, position_index);

        let pool = borrow_global_mut<Pool>(pool_address);
        //assert_status(pool);
        update_rewarder(pool);

        // 1. 更新位置的费用和奖励
        let (tick_lower, tick_upper) = get_position_tick_range_by_pool(
            pool,
            position_index
        );
        let (fee_growth_inside_a, fee_growth_inside_b) = get_fee_in_tick_range(
            pool,
            tick_lower,
            tick_upper
        );
        let rewards_growth_inside = get_reward_in_tick_range(pool, tick_lower, tick_upper);
        let position = pool.positions.borrow_mut(position_index);
        update_position_fee_and_reward(position, fee_growth_inside_a, fee_growth_inside_b, rewards_growth_inside);

        // 2. 更新位置的流动性
        update_position_liquidity(
            position,
            liquidity,
            false
        );

        // 3. 更新tick数据
        upsert_tick_by_liquidity(pool, tick_lower, liquidity, false, false);
        upsert_tick_by_liquidity(pool, tick_upper, liquidity, false, true);

        // 4. 更新池子的流动性并计算应返回的代币数量
        let (amount_a, amount_b) = clmm_math::get_amount_by_liquidity(
            tick_lower,
            tick_upper,
            pool.current_tick_index,
            pool.current_sqrt_price,
            liquidity,
            false,
        );
        let (after_liquidity, is_overflow) = if (i64::lte(tick_lower, pool.current_tick_index) && i64::lt(
            pool.current_tick_index,
            tick_upper
        )) {
            math_u128::overflowing_sub(pool.liquidity, liquidity)
        }else {
            (pool.liquidity, false)
        };
        if (is_overflow) {
            abort ELIQUIDITY_OVERFLOW
        };
        pool.liquidity = after_liquidity;

        // 发布移除流动性事件
        event::emit(RemoveLiquidityEvent {
            pool_address,
            tick_lower,
            tick_upper,
            liquidity,
            amount_a,
            amount_b,
            index: position_index
        });

        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        // 提取代币
        let asset_a = fungible_asset::withdraw(&pool_signer, pool.store_a, amount_a);
        let asset_b = fungible_asset::withdraw(&pool_signer, pool.store_b, amount_b);
        (asset_a, asset_b)
    }

   // 检查并关闭位置
   //
   // 关闭一个流动性位置，但只有在满足特定条件时才能成功关闭：
   // 1. 位置的流动性为零
   // 2. 位置没有未收取的交易费用
   // 3. 位置没有未收取的奖励
   //
   // 参数：
   //     - account: 位置所有者
   //     - pool_address: 池子账户地址
   //     - position_index: 位置索引
   //
   // 返回：
   //     - is_closed: 是否成功关闭位置
    public fun checked_close_position(
        account: &signer,
        pool_address: address,
        position_index: u64
    ): bool acquires Pool {
        check_position_authority(account, pool_address, position_index);
        let pool = borrow_global_mut<Pool>(pool_address);
        //assert_status(pool);
        let position = pool.positions.borrow(position_index);

        // 1. 检查位置流动性是否为零
        if (position.liquidity != 0) {
            return false
        };
        // 2. 检查是否有未收取的交易费用
        if (position.fee_owed_a > 0 || position.fee_owed_b > 0) {
            return false
        };
        // 3. 检查是否有未收取的奖励
        let i = 0;
        while (i < REWARDER_NUM) {
            if (position.rewarder_infos.borrow(i).amount_owed != 0) {
                return false
            };
            i += 1;
        };

        // 4. 从池子中移除位置
        pool.positions.remove(position_index);

        // 5. 销毁位置NFT
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        let user_address = signer::address_of(account);
        position_nft::burn(
            &pool_signer,
            user_address,
            pool.collection_name,
            pool.index,
            position_index
        );

        // 发布关闭位置事件
        event::emit(ClosePositionEvent {
            user: user_address,
            pool: pool_address,
            index: position_index
        });

        true
    }

   // 收集位置的流动性费用
   //
   // 收集位置产生的交易费用分成。费用来自于在该位置价格区间内进行的交易。
   // 可以选择是否重新计算费用，以确保获得最新的费用分成。
   //
   // 参数：
   //     - account: 位置所有者
   //     - pool_address: 池子地址
   //     - position_index: 位置索引
   //     - recalculate: 是否重新计算位置费用
   //
   // 返回：
   //     - coin_a: 位置的代币A费用
   //     - coin_b: 位置的代币B费用
    public fun collect_fee(
        account: &signer,
        pool_address: address,
        position_index: u64,
        recalculate: bool,
    ): (FungibleAsset, FungibleAsset) acquires Pool {
        check_position_authority(account, pool_address, position_index);
        let pool = borrow_global_mut<Pool>(pool_address);
        //assert_status(pool);

        let position = if (recalculate) {
            // 重新计算费用：获取位置的tick范围并更新费用
            let (tick_lower, tick_upper) = get_position_tick_range_by_pool(
                pool,
                position_index
            );
            let (fee_growth_inside_a, fee_growth_inside_b) = get_fee_in_tick_range(
                pool,
                tick_lower,
                tick_upper
            );
            let position = pool.positions.borrow_mut(position_index);
            update_position_fee(position, fee_growth_inside_a, fee_growth_inside_b);
            position
        } else {
            // 直接使用当前的费用计算结果
            pool.positions.borrow_mut(position_index)
        };

        // 获取应收费用
        let (amount_a, amount_b) = (position.fee_owed_a, position.fee_owed_b);
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        // 提取代币
        let asset_a = fungible_asset::withdraw(&pool_signer, pool.store_a, amount_a);
        let asset_b = fungible_asset::withdraw(&pool_signer, pool.store_b, amount_b);

        // 重置位置费用
        position.fee_owed_a = 0;
        position.fee_owed_b = 0;

        // 发布收集费用事件
        event::emit(CollectFeeEvent {
            pool_address,
            user: signer::address_of(account),
            amount_a,
            amount_b,
            index: position_index,
        });

        (asset_a, asset_b)
    }

   // 收集位置的流动性挖矿奖励
   //
   // 收集指定奖励器的奖励代币。奖励来自于流动性挖矿计划，
   // 按照流动性提供者的贡献比例分配。支持收集最多3种不同的奖励代币。
   //
   // 参数：
   //     - account: 位置所有者
   //     - pool_address: 池子地址
   //     - position_index: 位置索引
   //     - rewarder_index: 奖励器索引（0-2）
   //     - recalculate: 是否重新计算位置奖励
   //
   // 返回：
   //     - coin: 奖励代币
    public fun collect_rewarder(
        account: &signer,
        pool_address: address,
        position_index: u64,
        rewarder_index: u8,
        recalculate: bool,
    ): FungibleAsset acquires Pool {
        check_position_authority(account, pool_address, position_index);

        let pool = borrow_global_mut<Pool>(pool_address);
        //assert_status(pool);
        // 更新奖励器状态
        update_rewarder(pool);

        let position = if (recalculate) {
            // 重新计算奖励：获取位置的tick范围并更新奖励
            let (tick_lower, tick_upper) = get_position_tick_range_by_pool(
                pool,
                position_index
            );
            let rewards_growth_inside = get_reward_in_tick_range(pool, tick_lower, tick_upper);
            let position = pool.positions.borrow_mut(position_index);
            update_position_rewarder(position, rewards_growth_inside);
            position
        } else {
            // 直接使用当前的奖励计算结果
            pool.positions.borrow_mut(position_index)
        };

        // 获取奖励代币并重置应得奖励
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        let amount = &mut position.rewarder_infos.borrow_mut((rewarder_index as u64)).amount_owed;
        // TODO: 需要获取奖励代币的metadata，这里需要从pool的rewarder_infos中获取
        let rewarder_token = pool.rewarder_infos.borrow((rewarder_index as u64)).token;
        let rewarder_coin = fungible_asset::withdraw(&pool_signer, rewarder_token, *amount);

        *amount = 0;

        // 发布收集奖励事件
        event::emit(CollectRewardEvent {
            pool_address,
            user: signer::address_of(account),
            amount: fungible_asset::amount(&rewarder_coin),
            pos_index: position_index,
            index: rewarder_index,
        });

        rewarder_coin
    }

   // 更新池子的位置NFT集合和代币URI
   //
   // 允许有权限的账户更新池子位置NFT的显示URI，
   // 这会影响NFT在钱包和市场中的显示效果。
   //
   // 参数：
   //     - account: 设置者（需要有相应权限）
   //     - pool_address: 池子地址
   //     - uri: 新的URI
    public fun update_pool_uri(
        account: &signer,
        pool_address: address,
        uri: String
    ) acquires Pool {
        // 确保URI不为空
        assert!(!uri.is_empty(), EINVALID_POOL_URI);
        // 验证账户有设置NFT URI的权限
        assert!(config::allow_set_position_nft_uri(account), ENOT_HAS_PRIVILEGE);
        let pool = borrow_global_mut<Pool>(pool_address);
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        // 更新NFT集合的URI
        position_nft::mutate_collection_uri(&pool_signer, pool.collection_name, uri);
        pool.uri = uri;
    }

   // 闪电交换 - DEX的核心交易功能
   //
   // 这是集中流动性DEX的核心交易函数，实现了高效的代币交换。
   // 支持两种交换模式：固定输入量或固定输出量。
   // 使用闪电贷模式，先提供输出代币，后收取输入代币，确保原子性。
   //
   // 交换过程：
   // 1. 计算交换路径和价格影响
   // 2. 更新池子状态（价格、流动性、tick）
   // 3. 立即提供输出代币
   // 4. 返回收据，要求用户稍后支付输入代币
   //
   // 参数：
   //     - pool_address: 池子地址
   //     - swap_from: 交换发起者地址（用于事件记录）
   //     - partner_name: 合作伙伴名称（用于费用分成）
   //     - a2b: 交换方向（true: A换B, false: B换A）
   //     - by_amount_in: 按输入量还是输出量计算（true: 固定输入, false: 固定输出）
   //     - amount: 数量（根据by_amount_in决定是输入量还是输出量）
   //     - sqrt_price_limit: 价格滑点保护限制
   //
   // 返回：
   //     - coin_a: 输出的代币A（如果a2b为true则为零）
   //     - coin_b: 输出的代币B（如果a2b为false则为零）
   //     - receipt: 闪电贷收据（热土豆，必须立即处理）
    public fun flash_swap(
        pool_address: address,
        swap_from: address,
        partner_name: String,
        a2b: bool,
        by_amount_in: bool,
        amount: u64,
        sqrt_price_limit: u128,
    ): (FungibleAsset, FungibleAsset, FlashSwapReceipt) acquires Pool {
        // 获取合作伙伴推荐费率和协议费率
        let ref_fee_rate = partner::get_ref_fee_rate(partner_name);
        let protocol_fee_rate = config::get_protocol_fee_rate();

        let pool = borrow_global_mut<Pool>(pool_address);
        assert_status(pool);
        // 更新奖励器状态
        update_rewarder(pool);

        // 验证价格滑点限制
        if (a2b) {
            // A换B时，价格应该下降，所以当前价格必须大于限制价格
            assert!(
                pool.current_sqrt_price > sqrt_price_limit && sqrt_price_limit >= min_sqrt_price(),
                EWRONG_SQRT_PRICE_LIMIT
            );
        } else {
            // B换A时，价格应该上升，所以当前价格必须小于限制价格
            assert!(
                pool.current_sqrt_price < sqrt_price_limit && sqrt_price_limit <= max_sqrt_price(),
                EWRONG_SQRT_PRICE_LIMIT
            );
        };

        // 执行池内交换逻辑
        let result = swap_in_pool(
            pool,
            a2b,
            by_amount_in,
            sqrt_price_limit,
            amount,
            protocol_fee_rate,
            ref_fee_rate
        );

        // 发布交换事件
        event::emit(SwapEvent {
            atob: a2b,
            pool_address,
            swap_from,
            partner: partner_name,
            amount_in: result.amount_in,
            amount_out: result.amount_out,
            ref_amount: result.ref_fee_amount,
            fee_amount: result.fee_amount,
            vault_a_amount: fungible_asset::balance(pool.store_a),
            vault_b_amount: fungible_asset::balance(pool.store_b),
        });

        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);

        // 根据交换方向提取相应的输出代币
        let (asset_a, asset_b) = if (a2b) {
            // A换B：输出代币B，代币A为零
            (fungible_asset::zero(pool.metadata_a), fungible_asset::withdraw(
                &pool_signer,
                pool.store_b,
                result.amount_out
            ))
        } else {
            // B换A：输出代币A，代币B为零
            (fungible_asset::withdraw(&pool_signer, pool.store_a, result.amount_out), fungible_asset::zero(
                pool.metadata_b
            ))
        };

        // 返回输出代币和交换收据
        (
            asset_a,
            asset_b,
            FlashSwapReceipt {
                pool_address,
                a2b,
                partner_name,
                pay_amount: result.amount_in + result.fee_amount,
                ref_fee_amount: result.ref_fee_amount
            }
        )
    }

   // 偿还闪电交换的代币
   //
   // 这是闪电交换的第二步，用户必须支付相应的代币来完成交换。
   // 该函数会验证支付金额的正确性，分配合作伙伴费用，并将代币存入池子。
   //
   // 参数：
   //     - coin_a: 代币A（如果是A换B则包含支付金额，否则为零）
   //     - coin_b: 代币B（如果是B换A则包含支付金额，否则为零）
   //     - receipt: 闪电交换收据（包含支付信息）
    public fun repay_flash_swap(
        asset_a: FungibleAsset,
        asset_b: FungibleAsset,
        receipt: FlashSwapReceipt
    ) acquires Pool {
        let FlashSwapReceipt {
            pool_address,
            a2b,
            partner_name,
            pay_amount,
            ref_fee_amount
        } = receipt;
        let pool = borrow_global_mut<Pool>(pool_address);

        if (a2b) {
            // A换B：用户需要支付代币A
            assert!(fungible_asset::amount(&asset_a) == pay_amount, EAMOUNT_INCORRECT);
            // 分配推荐费给合作伙伴
            if (ref_fee_amount > 0) {
                let ref_fee = fungible_asset::extract(&mut asset_a, ref_fee_amount);
                partner::receive_ref_fee(partner_name, ref_fee);
            };
            fungible_asset::deposit(pool.store_a, asset_a);
            fungible_asset::destroy_zero(asset_b);
        } else {
            // B换A：用户需要支付代币B
            assert!(fungible_asset::amount(&asset_b) == pay_amount, EAMOUNT_INCORRECT);
            // 分配推荐费给合作伙伴
            if (ref_fee_amount > 0) {
                let ref_fee = fungible_asset::extract(&mut asset_b, ref_fee_amount);
                partner::receive_ref_fee(partner_name, ref_fee);
            };
            fungible_asset::deposit(pool.store_b, asset_b);
            fungible_asset::destroy_zero(asset_a);
        }
    }

   // 收集协议费用
   //
   // 只有协议费用领取权限的账户可以收集累积的协议费用。
   // 协议费用来自于每笔交易费用中分配给协议的部分。
   //
   // 参数：
   //     - account: 有协议费用领取权限的账户
   //     - pool_address: 池子地址
   //
   // 返回：
   //     - (FungibleAsset,FungibleAsset): 协议费用代币
    public fun collect_protocol_fee(
        account: &signer,
        pool_address: address
    ): (FungibleAsset, FungibleAsset) acquires Pool {
        // 验证协议费用领取权限
        config::assert_protocol_fee_claim_authority(account);

        let pool = borrow_global_mut<Pool>(pool_address);
        //assert_status(pool_info);
        let amount_a = pool.fee_protocol_coin_a;
        let amount_b = pool.fee_protocol_coin_b;

        // 提取协议费用代币
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        // 提取代币
        let asset_a = fungible_asset::withdraw(&pool_signer, pool.store_a, amount_a);
        let asset_b = fungible_asset::withdraw(&pool_signer, pool.store_b, amount_b);

        // 重置协议费用计数器
        pool.fee_protocol_coin_a = 0;
        pool.fee_protocol_coin_b = 0;

        // 发布收集协议费用事件
        event::emit(CollectProtocolFeeEvent {
            pool_address,
            amount_a,
            amount_b
        });
        (asset_a, asset_b)
    }

   // 初始化奖励器
   //
   // 为池子创建一个新的流动性挖矿奖励器，用于激励用户提供流动性。
   // 每个池子最多支持3个奖励器，每个奖励器对应一种奖励代币。
   // 只有协议管理员可以初始化奖励器。
   //
   // 参数：
   //     - account: 协议权限签名者
   //     - pool_address: 池子地址
   //     - authority: 奖励器管理权限地址
   //     - index: 奖励器索引（必须按顺序添加）
    public fun initialize_rewarder(
        account: &signer,
        pool_address: address,
        authority: address,
        index: u64,
        reward_token: Object<Metadata>
    ) acquires Pool {
        // 验证协议权限
        config::assert_protocol_authority(account);
        let pool = borrow_global_mut<Pool>(pool_address);
        assert_status(pool);

        let rewarder_infos = &mut pool.rewarder_infos;
        // 确保索引连续且不超过最大数量
        assert!(rewarder_infos.length() == index && index < REWARDER_NUM, EINVALID_REWARD_INDEX);

        // 创建新奖励器
        let rewarder = Rewarder {
            token: reward_token,
            authority,
            pending_authority: DEFAULT_ADDRESS,
            emissions_per_second: 0,
            growth_global: 0
        };
        rewarder_infos.push_back(rewarder);
    }

   // 更新奖励器发放速率
   //
   // 设置或更新奖励器的代币发放速率，启动流动性挖矿。
   // 只有奖励器的管理权限地址可以调用此函数。
   // 需要确保池子有足够的奖励代币余额来支持至少一天的发放。
   //
   // 参数：
   //     - account: 奖励器管理权限账户
   //     - pool_address: 池子地址
   //     - index: 奖励器索引
   //     - emissions_per_second: 每秒发放的代币数量（X64格式）
    public fun update_emission(
        account: &signer,
        pool_address: address,
        index: u8,
        emissions_per_second: u128,
        reward_token: Object<Metadata>
    ) acquires Pool {
        let pool = borrow_global_mut<Pool>(pool_address);
        assert_status(pool);
        // 更新奖励器状态
        update_rewarder(pool);

        // 计算每天需要的奖励代币数量
        let emission_per_day = full_math_u128::mul_shr(DAYS_IN_SECONDS, emissions_per_second, 64);
        assert!((index as u64) < pool.rewarder_infos.length(), EINVALID_REWARD_INDEX);
        let rewarder = pool.rewarder_infos.borrow_mut((index as u64));

        // 验证权限和代币类型
        assert!(signer::address_of(account) == rewarder.authority, EREWARD_AUTH_ERROR);
        assert!(rewarder.token == reward_token, EREWARD_NOT_MATCH_WITH_INDEX);

        // 确保池子有足够的奖励代币余额
        // TODO: 余额检查需要为FungibleAsset重新实现
        assert!(
            primary_fungible_store::balance(pool_address, reward_token) >= (emission_per_day as u64),
            EREWARD_AMOUNT_INSUFFICIENT
        );

        // 更新发放速率
        rewarder.emissions_per_second = emissions_per_second;

        // 发布更新发放事件
        event::emit(UpdateEmissionEvent {
            pool_address,
            index,
            emissions_per_second
        })
    }

   // 转移奖励器权限
   //
   // 将奖励器的管理权限转移给新的地址。
   // 这是一个两步流程：先转移，然后新地址需要接受。
   // 只有当前的奖励器权限地址可以发起转移。
   //
   // 参数：
   //     - account: 当前奖励器权限账户
   //     - pool_address: 池子地址
   //     - index: 奖励器索引
   //     - new_authority: 新的权限地址
    public fun transfer_rewarder_authority(
        account: &signer,
        pool_address: address,
        index: u8,
        new_authority: address
    ) acquires Pool {
        let old_authority = signer::address_of(account);
        let pool_info = borrow_global_mut<Pool>(pool_address);
        assert_status(pool_info);
        assert!((index as u64) < pool_info.rewarder_infos.length(), EINVALID_REWARD_INDEX);

        let rewarder = pool_info.rewarder_infos.borrow_mut((index as u64));
        // 验证当前权限
        assert!(rewarder.authority == old_authority, EREWARD_AUTH_ERROR);
        // 设置待接受的新权限地址
        rewarder.pending_authority = new_authority;

        // 发布转移权限事件
        event::emit(TransferRewardAuthEvent {
            pool_address,
            index,
            old_authority,
            new_authority
        })
    }

   // 接受奖励器权限
   //
   // 新的权限地址接受奖励器管理权限，完成权限转移流程。
   // 只有被指定为待接受权限的地址才能调用此函数。
   //
   // 参数：
   //     - account: 新的权限账户
   //     - pool_address: 池子地址
   //     - index: 奖励器索引
    public fun accept_rewarder_authority(
        account: &signer,
        pool_address: address,
        index: u8,
    ) acquires Pool {
        let new_authority = signer::address_of(account);
        let pool_info = borrow_global_mut<Pool>(pool_address);
        assert_status(pool_info);
        assert!((index as u64) < pool_info.rewarder_infos.length(), EINVALID_REWARD_INDEX);

        let rewarder = pool_info.rewarder_infos.borrow_mut((index as u64));
        // 验证是否为待接受的权限地址
        assert!(rewarder.pending_authority == new_authority, EREWARD_AUTH_ERROR);

        // 完成权限转移
        rewarder.pending_authority = DEFAULT_ADDRESS;
        rewarder.authority = new_authority;

        // 发布接受权限事件
        event::emit(AcceptRewardAuthEvent {
            pool_address,
            index,
            authority: new_authority,
        })
    }

   // 检查位置所有权
   //
   // 验证账户是否拥有指定位置的NFT，确保只有位置所有者才能操作该位置。
   // 通过检查用户是否持有对应的位置NFT来验证所有权。
   //
   // 参数：
   //     - account: 待验证的账户
   //     - pool_address: 池子账户地址
   //     - position_index: 位置索引
    public fun check_position_authority(
        account: &signer,
        pool_address: address,
        position_index: u64
    ) acquires Pool {
        let pool = borrow_global<Pool>(pool_address);
        // 检查位置是否存在
        if (!pool.positions.contains(position_index)) {
            abort EPOSITION_NOT_EXIST
        };

        let user_address = signer::address_of(account);
        let pool_address = account::get_signer_capability_address(&pool.signer_cap);

        // 构造位置NFT的标识符
        let position_name = position_nft::position_name(pool.index, position_index);
        let token_data_id = token::create_token_data_id(pool_address, pool.collection_name, position_name);
        let token_id = token::create_token_id(token_data_id, 0);

        // 验证用户是否持有该位置NFT
        assert!(token::balance_of(user_address, token_id) == 1, EPOSITION_OWNER_ERROR);
    }

    // 查看和获取函数
    // ============================================================================================================

   // 获取tick数据
   //
   // 分页获取池子中的tick数据，用于前端展示和分析。
   // 从指定索引和偏移量开始，获取指定数量的tick数据。
   //
   // 参数：
   //     - pool_address: 池子地址
   //     - index: 起始tick索引组
   //     - offset: 组内偏移量
   //     - limit: 获取数量限制
   //
   // 返回：
   //     - (下一个索引组, 下一个偏移量, tick数据向量)
    public fun fetch_ticks(
        pool_address: address, index: u64, offset: u64, limit: u64
    ): (u64, u64, vector<Tick>) acquires Pool {
        let pool = borrow_global_mut<Pool>(pool_address);
        let tick_spacing = pool.tick_spacing;
        let max_indexes_index = tick_indexes_max(tick_spacing);
        let search_indexes_index = index;
        let ticks = vector::empty<Tick>();
        let offset = offset;
        let count = 0;
        while ((search_indexes_index >= 0) && (search_indexes_index <= max_indexes_index)) {
            if (pool.tick_indexes.contains(search_indexes_index)) {
                let indexes = pool.tick_indexes.borrow(search_indexes_index);
                while ((offset >= 0) && (offset < TICK_INDEXES_LENGTH)) {
                    if (indexes.is_index_set(offset)) {
                        let tick_idx = i64::sub(
                            i64::from((TICK_INDEXES_LENGTH * search_indexes_index + offset) * tick_spacing),
                            tick_max(tick_spacing)
                        );
                        let tick = pool.ticks.borrow(tick_idx);
                        count += 1;
                        ticks.push_back(*tick);
                        if (count == limit) {
                            return (search_indexes_index, offset, ticks)
                        }
                    };
                    offset += 1;
                };
                offset = 0;
            };
            search_indexes_index += 1;
        };
        (search_indexes_index, offset, ticks)
    }

   // 获取位置数据
   //
   // 分页获取池子中的位置数据，用于前端展示用户的流动性位置。
   // 从指定索引开始，获取指定数量的位置数据。
   //
   // 参数：
   //     - pool_address: 池子地址
   //     - index: 起始位置索引
   //     - limit: 获取数量限制
   //
   // 返回：
   //     - (下一个索引, 位置数据向量)
    public fun fetch_positions(
        pool_address: address, index: u64, limit: u64
    ): (u64, vector<Position>) acquires Pool {
        let pool_info = borrow_global<Pool>(pool_address);
        let positions = vector::empty<Position>();
        let count = 0;
        while (count < limit && index < pool_info.position_index) {
            if (pool_info.positions.contains(index)) {
                let pos = pool_info.positions.borrow(index);
                positions.push_back(*pos);
                count += 1;
            };
            index += 1;
        };
        (index, positions)
    }

   // 计算交换结果
   //
   // 预先计算交换操作的详细结果，不实际执行交换。
   // 用于前端展示预期的交换结果、价格影响和滑点。
   // 模拟整个交换过程，包括跨tick的流动性变化。
   //
   // 参数：
   //     - pool_address: 池子地址
   //     - a2b: 交换方向（true: A换B, false: B换A）
   //     - by_amount_in: 按输入量还是输出量计算
   //     - amount: 输入量或输出量
   //
   // 返回：
   //     - swap_result: 详细的交换结果，包含每步的计算过程
   // 计算交换结果（不执行实际交换，仅计算）
   // 用于预估交换的输入输出量和费用
   //
   // 参数:
   //     pool_address: 池子地址
   //     a2b: 是否从A币交换到B币
   //     by_amount_in: 是否按输入量计算（true为按输入量，false为按输出量）
   //     amount: 交换数量
   // 返回:
   //     CalculatedSwapResult: 计算出的交换结果
    public fun calculate_swap_result(
        pool_address: address,
        a2b: bool,
        by_amount_in: bool,
        amount: u64,
    ): CalculatedSwapResult acquires Pool {
        // 获取池子信息（只读）
        let pool = borrow_global<Pool>(pool_address);
        let current_sqrt_price = pool.current_sqrt_price;  // 当前sqrt价格
        let current_liquidity = pool.liquidity;  // 当前流动性
        let swap_result = default_swap_result();  // 初始化交换结果
        let remainer_amount = amount;  // 剩余待交换数量
        let next_tick_idx = pool.current_tick_index;  // 下一个tick索引
        let (min_tick, max_tick) = (tick_min(pool.tick_spacing), tick_max(pool.tick_spacing));  // tick范围
        // 初始化计算结果结构
        let result = CalculatedSwapResult {
            amount_in: 0, // 输入量
            amount_out: 0, // 输出量
            fee_amount: 0, // 费用
            fee_rate: pool.fee_rate, // 费率
            after_sqrt_price: pool.current_sqrt_price, // 交换后价格
            is_exceed: false, // 是否超出范围
            step_results: vector::empty(), // 每步结果
        };
        // 逐步计算交换过程
        while (remainer_amount > 0) {
            // 检查是否超出tick范围
            if (i64::gt(next_tick_idx, max_tick) || i64::lt(next_tick_idx, min_tick)) {
                result.is_exceed = true;  // 标记超出范围
                break
            };
            // 获取下一个tick
            let opt_next_tick = get_next_tick_for_swap(pool, next_tick_idx, a2b, max_tick);
            if (opt_next_tick.is_none()) {
                result.is_exceed = true;  // 没有下一个tick，标记超出范围
                break
            };
            let next_tick: Tick = opt_next_tick.destroy_some();
            let target_sqrt_price = next_tick.sqrt_price;  // 目标sqrt价格
            // 计算单步交换结果
            let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
                current_sqrt_price,
                target_sqrt_price,
                current_liquidity,
                remainer_amount,
                pool.fee_rate,
                a2b,
                by_amount_in
            );

            // 如果有实际交换发生
            if (amount_in != 0 || fee_amount != 0) {
                // 根据计算方式更新剩余数量
                if (by_amount_in) {
                    // 按输入量计算：减去输入量和费用
                    remainer_amount = check_sub_remainer_amount(remainer_amount, amount_in);
                    remainer_amount = check_sub_remainer_amount(remainer_amount, fee_amount);
                } else {
                    // 按输出量计算：减去输出量
                    remainer_amount = check_sub_remainer_amount(remainer_amount, amount_out);
                };
                // 更新交换结果
                update_swap_result(&mut swap_result, amount_in, amount_out, fee_amount);
            };
            // 记录每步的详细结果
            result.step_results.push_back(SwapStepResult {
                current_sqrt_price, // 当前价格
                target_sqrt_price, // 目标价格
                current_liquidity, // 当前流动性
                amount_in, // 输入量
                amount_out, // 输出量
                fee_amount, // 费用
                remainer_amount      // 剩余数量
            });
            // 检查是否跨越了tick边界
            if (next_sqrt_price == next_tick.sqrt_price) {
                // 跨越tick边界，更新价格和流动性
                current_sqrt_price = next_tick.sqrt_price;
                // 计算流动性变化量（根据交换方向）
                let liquidity_change = if (a2b) {
                    i128::neg(next_tick.liquidity_net)  // A到B：减去流动性
                } else {
                    next_tick.liquidity_net  // B到A：加上流动性
                };
                // 更新池子当前流动性
                if (!is_neg(liquidity_change)) {
                    // 流动性增加
                    let (pool_liquidity, overflowing) = math_u128::overflowing_add(
                        current_liquidity,
                        i128::abs_u128(liquidity_change)
                    );
                    if (overflowing) {
                        abort ELIQUIDITY_OVERFLOW  // 流动性溢出
                    };
                    current_liquidity = pool_liquidity;
                } else {
                    // 流动性减少
                    let (pool_liquidity, overflowing) = math_u128::overflowing_sub(
                        current_liquidity,
                        i128::abs_u128(liquidity_change)
                    );
                    if (overflowing) {
                        abort ELIQUIDITY_UNDERFLOW  // 流动性下溢
                    };
                    current_liquidity = pool_liquidity;
                };
            } else {
                // 未跨越tick边界，只更新价格
                current_sqrt_price = next_sqrt_price;
            };
            // 更新下一个tick索引
            if (a2b) {
                next_tick_idx = i64::sub(next_tick.index, i64::from(1));  // A到B：向左移动
            } else {
                next_tick_idx = next_tick.index;  // B到A：向右移动
            };
        };

        // 设置最终结果
        result.amount_in = swap_result.amount_in;  // 总输入量
        result.amount_out = swap_result.amount_out;  // 总输出量
        result.fee_amount = swap_result.fee_amount;  // 总费用
        result.after_sqrt_price = current_sqrt_price;  // 交换后价格
        result
    }

   // 获取闪电交换的支付金额
   //
   // 参数:
   //     receipt: 闪电交换收据
   // 返回:
   //     u64: 需要支付的金额
    public fun swap_pay_amount(receipt: &FlashSwapReceipt): u64 {
        receipt.pay_amount
    }

   // 获取添加流动性的支付金额
   //
   // 参数:
   //     receipt: 添加流动性收据
   // 返回:
   //     (u64, u64): (A币数量, B币数量)
    public fun add_liqudity_pay_amount(
        receipt: &AddLiquidityReceipt
    ): (u64, u64) {
        (receipt.amount_a, receipt.amount_b)
    }

   // 获取池子的tick间距
   //
   // 参数:
   //     pool: 池子地址
   // 返回:
   //     u64: tick间距
    public fun get_tick_spacing(pool: address): u64 acquires Pool {
        if (!exists<Pool>(pool)) {
            abort EPOOL_NOT_EXISTS  // 池子不存在
        };
        let pool_info = borrow_global<Pool>(pool);
        pool_info.tick_spacing
    }

   // 获取池子的当前流动性
   //
   // 参数:
   //     pool: 池子地址
   // 返回:
   //     u128: 当前流动性
    public fun get_pool_liquidity(pool: address): u128 acquires Pool {
        if (!exists<Pool>(pool)) {
            abort EPOOL_NOT_EXISTS  // 池子不存在
        };
        let pool_info = borrow_global<Pool>(pool);
        pool_info.liquidity
    }

   // 获取池子的索引
   //
   // 参数:
   //     pool: 池子地址
   // 返回:
   //     u64: 池子索引
    public fun get_pool_index(pool: address): u64 acquires Pool {
        let pool_info = borrow_global<Pool>(pool);
        pool_info.index
    }

   // 获取位置信息
   //
   // 参数:
   //     pool_address: 池子地址
   //     pos_index: 位置索引
   // 返回:
   //     Position: 位置信息
    public fun get_position(
        pool_address: address,
        pos_index: u64
    ): Position acquires Pool {
        let pool_info = borrow_global<Pool>(pool_address);
        if (!pool_info.positions.contains(pos_index)) {
            abort EPOSITION_NOT_EXIST  // 位置不存在
        };
        *pool_info.positions.borrow(pos_index)
    }

   // 通过池子信息获取位置的tick范围
   //
   // 参数:
   //     pool_info: 池子信息引用
   //     position_index: 位置索引
   // 返回:
   //     (I64, I64): (下界tick, 上界tick)
    public fun get_position_tick_range_by_pool(
        pool_info: &Pool,
        position_index: u64
    ): (I64, I64) {
        if (!pool_info.positions.contains(position_index)) {
            abort EPOSITION_NOT_EXIST  // 位置不存在
        };
        let position = pool_info.positions.borrow(position_index);
        (position.tick_lower_index, position.tick_upper_index)
    }

   // 获取位置的tick范围
   //
   // 参数:
   //     pool_address: 池子地址
   //     position_index: 位置索引
   // 返回:
   //     (I64, I64): (下界tick, 上界tick)
    public fun get_position_tick_range(
        pool_address: address,
        position_index: u64
    ): (I64, I64) acquires Pool {
        let pool_info = borrow_global<Pool>(pool_address);
        if (!pool_info.positions.contains(position_index)) {
            abort EPOSITION_NOT_EXIST  // 位置不存在
        };
        let position = pool_info.positions.borrow(position_index);
        (position.tick_lower_index, position.tick_upper_index)
    }

   // 获取奖励器数量
   //
   // 参数:
   //     pool_address: 池子地址
   // 返回:
   //     u8: 奖励器数量
    public fun get_rewarder_len(pool_address: address): u8 acquires Pool {
        let pool_info = borrow_global<Pool>(pool_address);
        let len = pool_info.rewarder_infos.length();
        return (len as u8)
    }

    // 私有函数
    //============================================================================================================

   // 检查池子状态
   // 验证协议状态和池子是否暂停
    fun assert_status(pool: &Pool) {
        config::assert_protocol_status();  // 检查协议状态
        if (pool.is_pause) {
            abort EPOOL_IS_PAUDED  // 池子已暂停
        };
    }

   // 获取tick在索引数组中的位置
   //
   // 参数:
   //     tick: tick值
   //     tick_spacing: tick间距
   // 返回:
   //     u64: tick索引数组的索引
    fun tick_indexes_index(tick: I64, tick_spacing: u64): u64 {
        let num = i64::sub(tick, tick_min(tick_spacing));  // 计算相对于最小tick的偏移
        if (i64::is_neg(num)) {
            abort EINVALID_TICK  // tick无效
        };
        let denom = tick_spacing * TICK_INDEXES_LENGTH;  // 每个索引数组覆盖的tick范围
        i64::as_u64(num) / denom  // 计算索引数组位置
    }

   // 获取tick在存储中的位置
   // 返回tick索引数组的索引和在该数组中的偏移量
   //
   // 参数:
   //     tick: tick值
   //     tick_spacing: tick间距
   // 返回:
   //     (u64, u64): (索引数组索引, 在索引数组中的偏移量)
    fun tick_position(tick: I64, tick_spacing: u64): (u64, u64) {
        let index = tick_indexes_index(tick, tick_spacing);  // 获取索引数组位置
        let u_tick = i64::as_u64(i64::add(tick, tick_max(tick_spacing)));  // 转换为无符号并加上最大tick
        let offset = (u_tick - (index * tick_spacing * TICK_INDEXES_LENGTH)) / tick_spacing;  // 计算偏移量
        (index, offset)
    }

   // 获取tick在索引数组中的偏移量
   //
   // 参数:
   //     indexes_index: 索引数组的索引
   //     tick_spacing: tick间距
   //     tick: tick值
   // 返回:
   //     u64: tick在索引数组中的偏移量
    fun tick_offset(indexes_index: u64, tick_spacing: u64, tick: I64): u64 {
        let u_tick = i64::as_u64(i64::add(tick, tick_max(tick_spacing)));  // 转换为无符号并加上最大tick
        (u_tick - (indexes_index * tick_spacing * TICK_INDEXES_LENGTH)) / tick_spacing  // 计算偏移量
    }

   // 获取最大tick索引数组索引
   //
   // 参数:
   //     tick_spacing: tick间距
   // 返回:
   //     u64: 最大索引数组索引
    fun tick_indexes_max(tick_spacing: u64): u64 {
        ((tick_math::tick_bound() * 2) / (tick_spacing * TICK_INDEXES_LENGTH)) + 1  // 计算最大索引
        //let max_tick = tick_max(tick_spacing);
        //tick_indexes_index(max_tick, tick_spacing)
    }

   // 获取指定tick间距下的最小tick边界
   //
   // 参数:
   //     tick_spacing: tick间距
   // 返回:
   //     I64: 最小tick边界
    fun tick_min(tick_spacing: u64): I64 {
        let min_tick = tick_math::min_tick();  // 获取理论最小tick
        let mod = i64::mod(min_tick, i64::from(tick_spacing));  // 计算余数
        i64::sub(min_tick, mod)  // 调整到tick间距的倍数
    }

   // 获取指定tick间距下的最大tick边界
   //
   // 参数:
   //     tick_spacing: tick间距
   // 返回:
   //     I64: 最大tick边界
    fun tick_max(tick_spacing: u64): I64 {
        let max_tick = tick_math::max_tick();  // 获取理论最大tick
        let mod = i64::mod(max_tick, i64::from(tick_spacing));  // 计算余数
        i64::sub(max_tick, mod)  // 调整到tick间距的倍数
    }

   // 获取指定tick范围内的费用增长率
   //
   // 参数:
   //     pool: 池子引用
   //     tick_lower_index: 下界tick索引
   //     tick_upper_index: 上界tick索引
   // 返回:
   //     (u128, u128): (A币费用增长率, B币费用增长率)
    fun get_fee_in_tick_range(
        pool: &Pool,
        tick_lower_index: I64,
        tick_upper_index: I64
    ): (u128, u128) {
        let op_tick_lower = borrow_tick(pool, tick_lower_index);  // 获取下界tick
        let op_tick_upper = borrow_tick(pool, tick_upper_index);  // 获取上界tick
        let current_tick_index = pool.current_tick_index;  // 当前tick索引
        // 计算下界以下的费用增长率
        let (fee_growth_below_a, fee_growth_below_b) = if (op_tick_lower.is_none::<Tick>()) {
            // 下界tick不存在，使用全局增长率
            (pool.fee_growth_global_a, pool.fee_growth_global_b)
        }else {
            let tick_lower = op_tick_lower.borrow::<Tick>();
            if (i64::lt(current_tick_index, tick_lower_index)) {
                // 当前tick在下界以下，计算差值
                (math_u128::wrapping_sub(pool.fee_growth_global_a, tick_lower.fee_growth_outside_a),
                    math_u128::wrapping_sub(pool.fee_growth_global_b, tick_lower.fee_growth_outside_b))
            }else {
                // 当前tick在下界以上，使用tick的外部增长率
                (tick_lower.fee_growth_outside_a, tick_lower.fee_growth_outside_b)
            }
        };
        // 计算上界以上的费用增长率
        let (fee_growth_above_a, fee_growth_above_b) = if (op_tick_upper.is_none::<Tick>()) {
            // 上界tick不存在，增长率为0
            (0, 0)
        }else {
            let tick_upper = op_tick_upper.borrow::<Tick>();
            if (i64::lt(current_tick_index, tick_upper_index)) {
                // 当前tick在上界以下，使用tick的外部增长率
                (tick_upper.fee_growth_outside_a, tick_upper.fee_growth_outside_b)
            }else {
                // 当前tick在上界以上，计算差值
                (math_u128::wrapping_sub(pool.fee_growth_global_a, tick_upper.fee_growth_outside_a),
                    math_u128::wrapping_sub(pool.fee_growth_global_b, tick_upper.fee_growth_outside_b))
            }
        };
        // 返回范围内的费用增长率（全局 - 下界以下 - 上界以上）
        (
            math_u128::wrapping_sub(
                math_u128::wrapping_sub(pool.fee_growth_global_a, fee_growth_below_a),
                fee_growth_above_a
            ),
            math_u128::wrapping_sub(
                math_u128::wrapping_sub(pool.fee_growth_global_b, fee_growth_below_b),
                fee_growth_above_b
            )
        )
    }

   // 在池子中添加流动性（内部函数）
   //
   // 参数:
   //     pool_address: 池子地址
   //     position_index: 位置索引
   //     by_amount: 是否按数量计算流动性
   //     liquidity: 流动性数量
   //     amount: 代币数量
   //     fix_amount_a: 是否固定A币数量
   // 返回:
   //     AddLiquidityReceipt: 添加流动性收据
    fun add_liquidity_internal(
        pool_address: address,
        position_index: u64,
        by_amount: bool,
        liquidity: u128,
        amount: u64,
        fix_amount_a: bool
    ): AddLiquidityReceipt acquires Pool {
        // 1. 检查位置和池子状态
        let pool = borrow_global_mut<Pool>(pool_address);
        assert_status(pool);

        // 2. 更新奖励器
        update_rewarder(pool);

        // 3. 更新位置的费用和奖励
        let (tick_lower, tick_upper) = get_position_tick_range_by_pool(
            pool,
            position_index
        );
        let (fee_growth_inside_a, fee_growth_inside_b) = get_fee_in_tick_range(
            pool,
            tick_lower,
            tick_upper
        );
        let rewards_growth_inside = get_reward_in_tick_range(pool, tick_lower, tick_upper);
        let position = pool.positions.borrow_mut(position_index);
        update_position_fee_and_reward(position, fee_growth_inside_a, fee_growth_inside_b, rewards_growth_inside);

        // 4. 计算流动性和代币数量
        let (increase_liquidity, amount_a, amount_b) = if (by_amount) {
            // 按代币数量计算流动性
            clmm_math::get_liquidity_from_amount(
                tick_lower,
                tick_upper,
                pool.current_tick_index,
                pool.current_sqrt_price,
                amount,
                fix_amount_a,
            )
        } else {
            // 按流动性计算代币数量
            let (amount_a, amount_b) = clmm_math::get_amount_by_liquidity(
                tick_lower,
                tick_upper,
                pool.current_tick_index,
                pool.current_sqrt_price,
                liquidity,
                true
            );
            (liquidity, amount_a, amount_b)
        };

        // 5. 更新位置、池子tick的流动性
        update_position_liquidity(position, increase_liquidity, true);  // 更新位置流动性
        upsert_tick_by_liquidity(pool, tick_lower, increase_liquidity, true, false);  // 更新下界tick
        upsert_tick_by_liquidity(pool, tick_upper, increase_liquidity, true, true);   // 更新上界tick
        // 如果当前tick在位置范围内，更新池子流动性
        let (after_liquidity, is_overflow) = if (i64::gte(pool.current_tick_index, tick_lower) && i64::lt(
            pool.current_tick_index,
            tick_upper
        )) {
            math_u128::overflowing_add(pool.liquidity, increase_liquidity)
        } else {
            (pool.liquidity, false)
        };
        assert!(!is_overflow, ELIQUIDITY_OVERFLOW);  // 检查流动性溢出
        pool.liquidity = after_liquidity;

        // 发出事件
        event::emit(AddLiquidityEvent {
            pool_address,
            tick_lower,
            tick_upper,
            liquidity: increase_liquidity,
            amount_a,
            amount_b,
            index: position_index
        });

        // 返回添加流动性收据
        AddLiquidityReceipt {
            pool_address,
            amount_a,
            amount_b
        }
    }

   // 在池子中执行交换（内部函数）
   //
   // 参数:
   //     pool: 池子可变引用
   //     a2b: 是否从A币交换到B币
   //     by_amount_in: 是否按输入量计算
   //     sqrt_price_limit: sqrt价格限制
   //     amount: 交换数量
   //     protocol_fee_rate: 协议费用率
   //     ref_fee_rate: 推荐费用率
   // 返回:
   //     SwapResult: 交换结果
    fun swap_in_pool(
        pool: &mut Pool,
        a2b: bool,
        by_amount_in: bool,
        sqrt_price_limit: u128,
        amount: u64,
        protocol_fee_rate: u64,
        ref_fee_rate: u64,
    ): SwapResult {
        let swap_result = default_swap_result();  // 初始化交换结果
        let remainer_amount = amount;  // 剩余待交换数量
        let next_tick_idx = pool.current_tick_index;  // 下一个tick索引
        let (min_tick, max_tick) = (tick_min(pool.tick_spacing), tick_max(pool.tick_spacing));  // tick范围
        // 逐步执行交换
        while (remainer_amount > 0 && pool.current_sqrt_price != sqrt_price_limit) {
            // 检查是否超出tick范围
            if (i64::gt(next_tick_idx, max_tick) || i64::lt(next_tick_idx, min_tick)) {
                abort ENOT_ENOUGH_LIQUIDITY  // 流动性不足
            };
            // 获取下一个tick
            let opt_next_tick = get_next_tick_for_swap(pool, next_tick_idx, a2b, max_tick);
            if (opt_next_tick.is_none()) {
                abort ENOT_ENOUGH_LIQUIDITY  // 没有下一个tick，流动性不足
            };
            let next_tick: Tick = opt_next_tick.destroy_some();

            // 确定目标sqrt价格
            let target_sqrt_price = if (a2b) {
                math_u128::max(sqrt_price_limit, next_tick.sqrt_price)  // A到B：取较大值
            } else {
                math_u128::min(sqrt_price_limit, next_tick.sqrt_price)  // B到A：取较小值
            };
            // 计算单步交换结果
            let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
                pool.current_sqrt_price,
                target_sqrt_price,
                pool.liquidity,
                remainer_amount,
                pool.fee_rate,
                a2b,
                by_amount_in
            );
            // 如果有实际交换发生
            if (amount_in != 0 || fee_amount != 0) {
                // 根据计算方式更新剩余数量
                if (by_amount_in) {
                    remainer_amount = check_sub_remainer_amount(remainer_amount, amount_in);
                    remainer_amount = check_sub_remainer_amount(remainer_amount, fee_amount);
                } else {
                    remainer_amount = check_sub_remainer_amount(remainer_amount, amount_out);
                };

                // 更新交换结果
                update_swap_result(&mut swap_result, amount_in, amount_out, fee_amount);

                // 更新池子的费用
                swap_result.ref_fee_amount = update_pool_fee(pool, fee_amount, ref_fee_rate, protocol_fee_rate, a2b);
            };
            // 检查是否跨越了tick边界
            if (next_sqrt_price == next_tick.sqrt_price) {
                // 跨越tick边界，更新价格和tick索引
                pool.current_sqrt_price = next_tick.sqrt_price;
                pool.current_tick_index = if (a2b) {
                    i64::sub(next_tick.index, i64::from(1))  // A到B：向左移动
                } else {
                    next_tick.index  // B到A：向右移动
                };
                // 跨越tick，更新池子流动性和tick的外部费用增长率
                cross_tick_and_update_liquidity(pool, next_tick.index, a2b);
            } else {
                // 未跨越tick边界，只更新价格和tick索引
                pool.current_sqrt_price = next_sqrt_price;
                pool.current_tick_index = tick_math::get_tick_at_sqrt_price(next_sqrt_price);
            };
            // 更新下一个tick索引
            if (a2b) {
                next_tick_idx = i64::sub(next_tick.index, i64::from(1));  // A到B：向左移动
            } else {
                next_tick_idx = next_tick.index;  // B到A：向右移动
            };
        };

        swap_result  // 返回交换结果
    }

   // 更新奖励器
   // 在交换、添加流动性、移除流动性、收集奖励和更新发放速率时需要更新奖励器
    fun update_rewarder(
        pool: &mut Pool,
    ) {
        let current_time = timestamp::now_seconds();  // 当前时间
        let last_time = pool.rewarder_last_updated_time;  // 上次更新时间
        pool.rewarder_last_updated_time = current_time;  // 更新最后更新时间
        assert!(last_time <= current_time, EINVALID_TIME);  // 检查时间有效性
        // 如果流动性为0或时间未变化，直接返回
        if (pool.liquidity == 0 || current_time == last_time) {
            return
        };
        let time_delta = (current_time - last_time);  // 时间差
        let idx = 0;
        // 更新所有奖励器
        while (idx < pool.rewarder_infos.length()) {
            let emission = pool.rewarder_infos.borrow(idx).emissions_per_second;  // 每秒发放量
            // 计算奖励增长率增量
            let rewarder_grothw_delta = full_math_u128::mul_div_floor(
                (time_delta as u128),
                emission,
                pool.liquidity
            );
            let last_growth_global = pool.rewarder_infos.borrow(idx).growth_global;  // 上次全局增长率
            pool.rewarder_infos.borrow_mut(idx).growth_global = last_growth_global + rewarder_grothw_delta;  // 更新全局增长率
            idx += 1;
        }
    }

   // 更新交换结果
   //
   // 参数:
   //     result: 交换结果引用
   //     amount_in: 输入量
   //     amount_out: 输出量
   //     fee_amount: 费用
    fun update_swap_result(result: &mut SwapResult, amount_in: u64, amount_out: u64, fee_amount: u64) {
        // 累加输入量并检查溢出
        let (result_amount_in, overflowing) = math_u64::overflowing_add(result.amount_in, amount_in);
        if (overflowing) {
            abort ESWAP_AMOUNT_IN_OVERFLOW  // 输入量溢出
        };
        // 累加输出量并检查溢出
        let (result_amount_out, overflowing) = math_u64::overflowing_add(result.amount_out, amount_out);
        if (overflowing) {
            abort ESWAP_AMOUNT_OUT_OVERFLOW  // 输出量溢出
        };
        // 累加费用并检查溢出
        let (result_fee_amount, overflowing) = math_u64::overflowing_add(result.fee_amount, fee_amount);
        if (overflowing) {
            abort ESWAP_FEE_AMOUNT_OVERFLOW  // 费用溢出
        };
        // 更新结果
        result.amount_out = result_amount_out;
        result.amount_in = result_amount_in;
        result.fee_amount = result_fee_amount;
    }

   // 更新池子的协议费用和全局费用增长率
   //
   // 参数:
   //     pool: 池子可变引用
   //     fee_amount: 总费用
   //     ref_rate: 推荐费用率
   //     protocol_fee_rate: 协议费用率
   //     a2b: 是否从A币交换到B币
   // 返回:
   //     u64: 推荐费用
    fun update_pool_fee(
        pool: &mut Pool,
        fee_amount: u64,
        ref_rate: u64,
        protocol_fee_rate: u64,
        a2b: bool
    ): u64 {
        let protocol_fee = full_math_u64::mul_div_ceil(
            fee_amount,
            protocol_fee_rate,
            PROTOCOL_FEE_DENOMNINATOR
        );  // 计算协议费用
        let liquidity_fee = fee_amount - protocol_fee;  // 流动性提供者费用
        // 计算推荐费用
        let ref_fee = if (ref_rate == 0) {
            0
        }else {
            full_math_u64::mul_div_floor(protocol_fee, ref_rate, PROTOCOL_FEE_DENOMNINATOR)
        };
        protocol_fee -= ref_fee;  // 减去推荐费用
        // 更新协议费用
        if (a2b) {
            pool.fee_protocol_coin_a = math_u64::wrapping_add(pool.fee_protocol_coin_a, protocol_fee);
        } else {
            pool.fee_protocol_coin_b = math_u64::wrapping_add(pool.fee_protocol_coin_b, protocol_fee);
        };
        // 如果流动性费用为0或池子流动性为0，直接返回推荐费用
        if (liquidity_fee == 0 || pool.liquidity == 0) {
            return ref_fee
        };
        // 计算费用增长率
        let growth_fee = ((liquidity_fee as u128) << 64) / pool.liquidity;
        // 更新全局费用增长率
        if (a2b) {
            pool.fee_growth_global_a = math_u128::wrapping_add(pool.fee_growth_global_a, growth_fee);
        } else {
            pool.fee_growth_global_b = math_u128::wrapping_add(pool.fee_growth_global_b, growth_fee);
        };
        ref_fee  // 返回推荐费用
    }

   // 跨越tick并更新流动性
   //
   // 参数:
   //     pool: 池子可变引用
   //     tick: tick索引
   //     a2b: 是否从A币交换到B币
    fun cross_tick_and_update_liquidity(
        pool: &mut Pool,
        tick: I64,
        a2b: bool
    ) {
        let tick = pool.ticks.borrow_mut(tick);  // 获取tick可变引用
        // 计算流动性变化量（根据交换方向）
        let liquidity_change = if (a2b) {
            i128::neg(tick.liquidity_net)  // A到B：减去流动性
        } else {
            tick.liquidity_net  // B到A：加上流动性
        };

        // 更新池子流动性
        if (!is_neg(liquidity_change)) {
            // 流动性增加
            let (pool_liquidity, overflowing) = math_u128::overflowing_add(
                pool.liquidity,
                i128::abs_u128(liquidity_change)
            );
            if (overflowing) {
                abort ELIQUIDITY_OVERFLOW  // 流动性溢出
            };
            pool.liquidity = pool_liquidity;
        } else {
            // 流动性减少
            let (pool_liquidity, overflowing) = math_u128::overflowing_sub(
                pool.liquidity,
                i128::abs_u128(liquidity_change)
            );
            if (overflowing) {
                abort ELIQUIDITY_UNDERFLOW  // 流动性下溢
            };
            pool.liquidity = pool_liquidity;
        };

        // 更新tick的外部费用增长率
        tick.fee_growth_outside_a =
            math_u128::wrapping_sub(pool.fee_growth_global_a, tick.fee_growth_outside_a);
        tick.fee_growth_outside_b =
            math_u128::wrapping_sub(pool.fee_growth_global_b, tick.fee_growth_outside_b);
        // 更新tick的奖励器外部增长率
        let idx = 0;
        while (idx < pool.rewarder_infos.length()) {
            let growth_global = pool.rewarder_infos.borrow(idx).growth_global;  // 全局增长率
            let rewarder_growth_outside = *tick.rewarders_growth_outside.borrow(idx);  // 当前外部增长率
            // 更新外部增长率（全局 - 当前外部）
            *tick.rewarders_growth_outside.borrow_mut(idx) = math_u128::wrapping_sub(growth_global,
                rewarder_growth_outside);
            idx += 1;
        }
    }

   // 检查并减去剩余数量
   //
   // 参数:
   //     remainer_amount: 剩余数量
   //     amount: 要减去的数量
   // 返回:
   //     u64: 减去后的剩余数量
    fun check_sub_remainer_amount(remainer_amount: u64, amount: u64): u64 {
        let (r_amount, overflowing) = math_u64::overflowing_sub(remainer_amount, amount);
        if (overflowing) {
            abort EREMAINER_AMOUNT_UNDERFLOW  // 剩余数量下溢
        };
        r_amount
    }

   // 获取交换的下一个tick
   // 在交换过程中寻找下一个有流动性的tick
   //
   // 参数:
   //     pool: 池子引用
   //     tick_idx: 当前tick索引
   //     a2b: 是否从A币交换到B币
   //     max_tick: 最大tick值
   // 返回:
   //     Option<Tick>: 下一个tick，如果没有则返回None
    fun get_next_tick_for_swap(
        pool: &Pool,
        tick_idx: I64,
        a2b: bool,
        max_tick: I64
    ): Option<Tick> {
        let tick_spacing = pool.tick_spacing;  // tick间距
        let max_indexes_index = tick_indexes_max(tick_spacing);  // 最大索引数组索引
        let (search_indexes_index, offset) = tick_position(tick_idx, tick_spacing);  // 获取搜索位置
        // 根据交换方向调整偏移量
        if (!a2b) {
            offset += 1;  // B到A：向右搜索
        };
        // 在索引数组范围内搜索
        while ((search_indexes_index >= 0) && (search_indexes_index <= max_indexes_index)) {
            if (pool.tick_indexes.contains(search_indexes_index)) {
                let indexes = pool.tick_indexes.borrow(search_indexes_index);
                // 在当前索引数组内搜索
                while ((offset >= 0) && (offset < TICK_INDEXES_LENGTH)) {
                    if (indexes.is_index_set(offset)) {
                        // 找到有流动性的tick，计算实际tick索引
                        let tick_idx = i64::sub(
                            i64::from((TICK_INDEXES_LENGTH * search_indexes_index + offset) * tick_spacing),
                            max_tick
                        );
                        let tick = pool.ticks.borrow(tick_idx);
                        return option::some(*tick)
                    };
                    // 根据交换方向移动偏移量
                    if (a2b) {
                        if (offset == 0) {
                            break  // A到B：向左搜索，到达边界
                        } else {
                            offset -= 1;
                        };
                    } else {
                        offset += 1;  // B到A：向右搜索
                    }
                };
            };
            // 移动到下一个索引数组
            if (a2b) {
                if (search_indexes_index == 0) {
                    return option::none<Tick>()  // A到B：到达最小索引
                };
                offset = TICK_INDEXES_LENGTH - 1;  // 重置到数组末尾
                search_indexes_index -= 1;  // 向左移动
            } else {
                offset = 0;  // 重置到数组开头
                search_indexes_index += 1;  // 向右移动
            }
        };

        option::none<Tick>()  // 未找到下一个tick
    }

   // 根据流动性变化更新tick
   // 添加或移除流动性时更新tick的状态
   //
   // 参数:
   //     pool: 池子可变引用
   //     tick_idx: tick索引
   //     delta_liquidity: 流动性变化量
   //     is_increase: 是否增加流动性
   //     is_upper_tick: 是否为上界tick
    fun upsert_tick_by_liquidity(
        pool: &mut Pool,
        tick_idx: I64,
        delta_liquidity: u128,
        is_increase: bool,
        is_upper_tick: bool
    ) {
        let tick = borrow_mut_tick_with_default(
            &mut pool.tick_indexes,
            &mut pool.ticks,
            pool.tick_spacing,
            tick_idx
        );  // 获取或创建tick
        if (delta_liquidity == 0) {
            return  // 没有流动性变化，直接返回
        };
        // 更新总流动性（gross liquidity）
        let (liquidity_gross, overflow) = if (is_increase) {
            math_u128::overflowing_add(tick.liquidity_gross, delta_liquidity)  // 增加流动性
        } else {
            math_u128::overflowing_sub(tick.liquidity_gross, delta_liquidity)  // 减少流动性
        };
        if (overflow) {
            abort ELIQUIDITY_OVERFLOW  // 流动性溢出
        };

        // 如果总流动性为零，从池子中移除这个tick
        if (liquidity_gross == 0) {
            remove_tick(pool, tick_idx);
            return
        };

        // 确定费用和奖励增长率
        let (fee_growth_outside_a, fee_growth_outside_b, reward_growth_outside) = if (tick.liquidity_gross == 0) {
            // 新tick：根据当前tick位置设置外部增长率
            if (i64::gte(pool.current_tick_index, tick_idx)) {
                // 当前tick在tick_idx以上，外部增长率等于全局增长率
                (pool.fee_growth_global_a, pool.fee_growth_global_b, rewarder_growth_globals(pool.rewarder_infos,
                ))
            } else {
                // 当前tick在tick_idx以下，外部增长率为0
                (0u128, 0u128, vector[0, 0, 0])
            }
        } else {
            // 已存在的tick：保持原有外部增长率
            (tick.fee_growth_outside_a, tick.fee_growth_outside_b, tick.rewarders_growth_outside)
        };
        // 更新净流动性（net liquidity）
        let (liquidity_net, overflow) = if (is_increase) {
            if (is_upper_tick) {
                i128::overflowing_sub(tick.liquidity_net, i128::from(delta_liquidity))  // 上界tick：减少净流动性
            } else {
                i128::overflowing_add(tick.liquidity_net, i128::from(delta_liquidity))  // 下界tick：增加净流动性
            }
        } else {
            if (is_upper_tick) {
                i128::overflowing_add(tick.liquidity_net, i128::from(delta_liquidity))  // 上界tick：增加净流动性
            } else {
                i128::overflowing_sub(tick.liquidity_net, i128::from(delta_liquidity))  // 下界tick：减少净流动性
            }
        };
        if (overflow) {
            abort ELIQUIDITY_OVERFLOW  // 流动性溢出
        };
        // 更新tick的所有字段
        tick.liquidity_gross = liquidity_gross;
        tick.liquidity_net = liquidity_net;
        tick.fee_growth_outside_a = fee_growth_outside_a;
        tick.fee_growth_outside_b = fee_growth_outside_b;
        tick.rewarders_growth_outside = reward_growth_outside;
    }

   // 创建默认tick结构体
   //
   // 参数:
   //     tick_idx: tick索引
   // 返回:
   //     Tick: 默认tick结构体
    fun default_tick(tick_idx: I64): Tick {
        Tick {
            index: tick_idx, // tick索引
            sqrt_price: tick_math::get_sqrt_price_at_tick(tick_idx), // 对应的sqrt价格
            liquidity_net: i128::from(0), // 净流动性为0
            liquidity_gross: 0, // 总流动性为0
            fee_growth_outside_a: 0, // A币外部费用增长率为0
            fee_growth_outside_b: 0, // B币外部费用增长率为0
            rewarders_growth_outside: vector<u128>[0, 0, 0], // 奖励器外部增长率为0
        }
    }

   // 借用一个tick（只读）
   //
   // 参数:
   //     pool: 池子引用
   //     tick_idx: tick索引
   // 返回:
   //     Option<Tick>: tick的只读引用，如果不存在则返回None
    fun borrow_tick(pool: &Pool, tick_idx: I64): Option<Tick> {
        let (index, _offset) = tick_position(tick_idx, pool.tick_spacing);  // 计算tick位置
        if (!pool.tick_indexes.contains(index)) {
            return option::none<Tick>()  // 索引数组不存在
        };
        if (!pool.ticks.contains(tick_idx)) {
            return option::none<Tick>()  // tick不存在
        };
        let tick = pool.ticks.borrow(tick_idx);  // 借用tick
        option::some(*tick)
    }


   // 创建默认交换结果
   //
   // 返回:
   //     SwapResult: 默认的交换结果结构体
    fun default_swap_result(): SwapResult {
        SwapResult {
            amount_in: 0, // 输入量为0
            amount_out: 0, // 输出量为0
            fee_amount: 0, // 费用为0
            ref_fee_amount: 0, // 推荐费用为0
        }
    }

   // 借用可变tick，如果不存在则创建默认tick
   // 主要用于测试存储
   //
   // 参数:
   //     tick_indexes: tick索引数组的可变引用
   //     ticks: tick表的可变引用
   //     tick_spacing: tick间距
   //     tick_idx: tick索引
   // 返回:
   //     &mut Tick: tick的可变引用
    fun borrow_mut_tick_with_default(
        tick_indexes: &mut Table<u64, BitVector>,
        ticks: &mut Table<I64, Tick>,
        tick_spacing: u64,
        tick_idx: I64,
    ): &mut Tick {
        let (index, offset) = tick_position(tick_idx, tick_spacing);  // 计算tick位置

        // 如果索引数组不存在则添加它
        if (!tick_indexes.contains(index)) {
            tick_indexes.add(index, bit_vector::new(TICK_INDEXES_LENGTH));
        };

        let indexes = tick_indexes.borrow_mut(index);
        indexes.set(offset);  // 设置位向量中的位

        // 如果tick不存在则创建默认tick，否则借用现有tick
        if (!ticks.contains(tick_idx)) {
            ticks.borrow_mut_with_default(tick_idx, default_tick(tick_idx))
        } else {
            ticks.borrow_mut(tick_idx)
        }
    }

   // 从池子中移除tick
   //
   // 参数:
   //     pool: 池子可变引用
   //     tick_idx: 要移除的tick索引
    fun remove_tick(
        pool: &mut Pool,
        tick_idx: I64
    ) {
        let (index, offset) = tick_position(tick_idx, pool.tick_spacing);  // 计算tick位置
        if (!pool.tick_indexes.contains(index)) {
            abort ETICK_INDEXES_NOT_SET  // 索引数组未设置
        };
        let indexes = pool.tick_indexes.borrow_mut(index);
        indexes.unset(offset);  // 清除位向量中的位
        if (!pool.ticks.contains(tick_idx)) {
            abort ETICK_NOT_FOUND  // tick未找到
        };
        pool.ticks.remove(tick_idx);  // 从表中移除tick
    }

   // 获取所有奖励器的全局增长率
   //
   // 参数:
   //     rewarders: 奖励器向量
   // 返回:
   //     vector<u128>: 全局增长率向量
    fun rewarder_growth_globals(rewarders: vector<Rewarder>): vector<u128> {
        let res = vector[0, 0, 0];  // 初始化结果向量
        let idx = 0;
        while (idx < rewarders.length()) {
            *res.borrow_mut(idx) = rewarders.borrow(idx).growth_global;  // 复制全局增长率
            idx += 1;
        };
        res
    }

   // 获取指定tick范围内的奖励增长率
   //
   // 参数:
   //     pool: 池子引用
   //     tick_lower_index: 下界tick索引
   //     tick_upper_index: 上界tick索引
   // 返回:
   //     vector<u128>: 范围内的奖励增长率向量
    fun get_reward_in_tick_range(
        pool: &Pool,
        tick_lower_index: I64,
        tick_upper_index: I64
    ): vector<u128> {
        let op_tick_lower = borrow_tick(pool, tick_lower_index);  // 获取下界tick
        let op_tick_upper = borrow_tick(pool, tick_upper_index);  // 获取上界tick
        let current_tick_index = pool.current_tick_index;  // 当前tick索引
        let res = vector::empty<u128>();  // 初始化结果向量
        let idx = 0;
        // 遍历所有奖励器
        while (idx < pool.rewarder_infos.length()) {
            let growth_blobal = pool.rewarder_infos.borrow(idx).growth_global;  // 全局增长率
            // 计算下界以下的奖励增长率
            let rewarder_growths_below = if (op_tick_lower.is_none::<Tick>()) {
                growth_blobal  // 下界tick不存在，使用全局增长率
            }else {
                let tick_lower = op_tick_lower.borrow::<Tick>();
                if (i64::lt(current_tick_index, tick_lower_index)) {
                    // 当前tick在下界以下，计算差值
                    math_u128::wrapping_sub(growth_blobal, *tick_lower.rewarders_growth_outside.borrow(idx))
                }else {
                    // 当前tick在下界以上，使用tick的外部增长率
                    *tick_lower.rewarders_growth_outside.borrow(idx)
                }
            };
            // 计算上界以上的奖励增长率
            let rewarder_growths_above = if (op_tick_upper.is_none::<Tick>()) {
                0  // 上界tick不存在，增长率为0
            }else {
                let tick_upper = op_tick_upper.borrow::<Tick>();
                if (i64::lt(current_tick_index, tick_upper_index)) {
                    // 当前tick在上界以下，使用tick的外部增长率
                    *tick_upper.rewarders_growth_outside.borrow(idx)
                }else {
                    // 当前tick在上界以上，计算差值
                    math_u128::wrapping_sub(growth_blobal, *tick_upper.rewarders_growth_outside.borrow(idx))
                }
            };
            // 计算范围内的奖励增长率（全局 - 下界以下 - 上界以上）
            let rewarder_inside = math_u128::wrapping_sub(
                math_u128::wrapping_sub(growth_blobal, rewarder_growths_below),
                rewarder_growths_above
            );
            res.push_back(rewarder_inside);
            idx += 1;
        };
        res
    }


   // 创建新的空位置
   //
   // 参数:
   //     pool_address: 池子地址
   //     tick_lower_index: 下界tick索引
   //     tick_upper_index: 上界tick索引
   //     index: 位置索引
   // 返回:
   //     Position: 新的空位置
    fun new_empty_position(
        pool_address: address,
        tick_lower_index: I64,
        tick_upper_index: I64,
        index: u64
    ): Position {
        Position {
            pool: pool_address, // 池子地址
            index, // 位置索引
            liquidity: 0, // 流动性为0
            tick_lower_index, // 下界tick索引
            tick_upper_index, // 上界tick索引
            fee_growth_inside_a: 0, // A币内部费用增长率为0
            fee_owed_a: 0, // A币应得费用为0
            fee_growth_inside_b: 0, // B币内部费用增长率为0
            fee_owed_b: 0, // B币应得费用为0
            rewarder_infos: vector[  // 奖励器信息（3个奖励器）
                PositionRewarder {
                    growth_inside: 0, // 内部增长率为0
                    amount_owed: 0, // 应得奖励为0
                },
                PositionRewarder {
                    growth_inside: 0,
                    amount_owed: 0,
                },
                PositionRewarder {
                    growth_inside: 0,
                    amount_owed: 0,
                },
            ],
        }
    }

   // 更新位置的奖励器信息
   //
   // 参数:
   //     position: 位置可变引用
   //     rewarder_growths_inside: 内部奖励增长率向量
    fun update_position_rewarder(position: &mut Position, rewarder_growths_inside: vector<u128>) {
        let idx = 0;
        while (idx < rewarder_growths_inside.length()) {
            let current_growth = *rewarder_growths_inside.borrow(idx);  // 当前增长率
            let rewarder = position.rewarder_infos.borrow_mut(idx);  // 获取奖励器信息
            let growth_delta = math_u128::wrapping_sub(current_growth, rewarder.growth_inside);  // 计算增长率差值
            // 计算应得奖励增量（增长率差值 * 流动性 / 2^64）
            let amount_owed_delta = full_math_u128::mul_shr(growth_delta, position.liquidity, 64);
            rewarder.growth_inside = current_growth;  // 更新内部增长率
            // 累加应得奖励并检查溢出
            let (latest_owned, is_overflow) = math_u64::overflowing_add(
                rewarder.amount_owed,
                (amount_owed_delta as u64)
            );
            assert!(!is_overflow, EREWARDER_OWNED_OVERFLOW);  // 检查奖励溢出
            rewarder.amount_owed = latest_owned;  // 更新应得奖励
            idx += 1;
        }
    }

   // 更新位置的费用信息
   //
   // 参数:
   //     position: 位置可变引用
   //     fee_growth_inside_a: A币内部费用增长率
   //     fee_growth_inside_b: B币内部费用增长率
    fun update_position_fee(position: &mut Position, fee_growth_inside_a: u128, fee_growth_inside_b: u128) {
        // 计算A币费用增长率差值
        let growth_delta_a = math_u128::wrapping_sub(fee_growth_inside_a, position.fee_growth_inside_a);
        // 计算A币应得费用增量（流动性 * 增长率差值 / 2^64）
        let fee_delta_a = full_math_u128::mul_shr(position.liquidity, growth_delta_a, 64);
        // 计算B币费用增长率差值
        let growth_delta_b = math_u128::wrapping_sub(fee_growth_inside_b, position.fee_growth_inside_b);
        // 计算B币应得费用增量
        let fee_delta_b = full_math_u128::mul_shr(position.liquidity, growth_delta_b, 64);
        // 累加A币应得费用并检查溢出
        let (fee_owed_a, is_overflow_a) = math_u64::overflowing_add(position.fee_owed_a, (fee_delta_a as u64));
        // 累加B币应得费用并检查溢出
        let (fee_owed_b, is_overflow_b) = math_u64::overflowing_add(position.fee_owed_b, (fee_delta_b as u64));
        assert!(!is_overflow_a, EFEE_OWNED_OVERFLOW);  // 检查A币费用溢出
        assert!(!is_overflow_b, EFEE_OWNED_OVERFLOW);  // 检查B币费用溢出

        // 更新位置的所有费用相关字段
        position.fee_owed_a = fee_owed_a;
        position.fee_owed_b = fee_owed_b;
        position.fee_growth_inside_a = fee_growth_inside_a;
        position.fee_growth_inside_b = fee_growth_inside_b;
    }

   // 更新位置的流动性
   //
   // 参数:
   //     position: 位置可变引用
   //     delta_liquidity: 流动性变化量
   //     is_increase: 是否增加流动性
    fun update_position_liquidity(
        position: &mut Position,
        delta_liquidity: u128,
        is_increase: bool
    ) {
        if (delta_liquidity == 0) {
            return  // 没有变化，直接返回
        };
        // 根据操作类型更新流动性
        let (liquidity, is_overflow) = {
            if (is_increase) {
                math_u128::overflowing_add(position.liquidity, delta_liquidity)  // 增加流动性
            }else {
                math_u128::overflowing_sub(position.liquidity, delta_liquidity)  // 减少流动性
            }
        };
        assert!(!is_overflow, EINVALID_DELTA_LIQUIDITY);  // 检查流动性变化是否有效
        position.liquidity = liquidity;  // 更新位置流动性
    }

   // 更新位置的费用和奖励信息
   //
   // 参数:
   //     position: 位置可变引用
   //     fee_growth_inside_a: A币内部费用增长率
   //     fee_growth_inside_b: B币内部费用增长率
   //     rewards_growth_inside: 内部奖励增长率向量
    fun update_position_fee_and_reward(
        position: &mut Position,
        fee_growth_inside_a: u128,
        fee_growth_inside_b: u128,
        rewards_growth_inside: vector<u128>,
    ) {
        update_position_fee(position, fee_growth_inside_a, fee_growth_inside_b);  // 更新费用
        update_position_rewarder(position, rewards_growth_inside);  // 更新奖励
    }
}
