module eden_clmm::clmm_router {
    use std::signer;
    use std::string::String;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::object::Object;
    use aptos_framework::primary_fungible_store;
    use integer_mate::i64;
    use eden_clmm::config;
    use eden_clmm::pool;
    use eden_clmm::factory;
    use eden_clmm::partner;
    use eden_clmm::fee_tier;

    const EAMOUNT_IN_ABOVE_MAX_LIMIT: u64 = 1;
    const EAMOUNT_OUT_BELOW_MIN_LIMIT: u64 = 2;
    const EIS_NOT_VALID_TICK: u64 = 3;
    const EINVALID_LIQUIDITY: u64 = 4;
    const EPOOL_ADDRESS_ERROR: u64 = 5;
    const EINVALID_POOL_PAIR: u64 = 6;
    const ESWAP_AMOUNT_INCORRECT: u64 = 7;
    const EPOSITION_INDEX_ERROR: u64 = 8;
    const EPOSITION_IS_NOT_ZERO: u64 = 9;

    // #[cmd]
    // Transfer the `protocol_authority` to new authority.
    // Params
    //     - next_protocol_authority
    // Returns
    public entry fun transfer_protocol_authority(
        protocol_authority: &signer, next_protocol_authority: address
    ) {
        config::transfer_protocol_authority(protocol_authority, next_protocol_authority);
    }

    // #[cmd]
    // Accept the `protocol_authority`.
    // Params
    // Returns
    public entry fun accept_protocol_authority(
        next_protocol_authority: &signer
    ) {
        config::accept_protocol_authority(next_protocol_authority);
    }

    // #[cmd]
    // Update the `protocol_fee_claim_authority`.
    // Params
    //     - next_protocol_fee_claim_authority
    // Returns
    public entry fun update_protocol_fee_claim_authority(
        protocol_authority: &signer, next_protocol_fee_claim_authority: address
    ) {
        config::update_protocol_fee_claim_authority(
            protocol_authority, next_protocol_fee_claim_authority
        );
    }

    // #[cmd]
    // Update the `pool_create_authority`.
    // Params
    //     - pool_create_authority
    // Returns
    public entry fun update_pool_create_authority(
        protocol_authority: &signer, pool_create_authority: address
    ) {
        config::update_pool_create_authority(protocol_authority, pool_create_authority);
    }

    // #[cmd]
    // Update the `protocol_fee_rate`, the protocol_fee_rate is unique and global for the clmmpool protocol.
    // Params
    //     - protocol_fee_rate
    // Returns
    public entry fun update_protocol_fee_rate(
        protocol_authority: &signer, protocol_fee_rate: u64
    ) {
        config::update_protocol_fee_rate(protocol_authority, protocol_fee_rate);
    }

    // #[cmd]
    // Add a new `fee_tier`. fee_tier is identified by the tick_spacing.
    // Params
    //     - tick_spacing
    //     - fee_rate
    // Returns
    public entry fun add_fee_tier(
        protocol_authority: &signer, tick_spacing: u64, fee_rate: u64
    ) {
        fee_tier::add_fee_tier(protocol_authority, tick_spacing, fee_rate);
    }

    // #[cmd]
    // Update the fee_rate of a fee_tier.
    // Params
    //     - tick_spacing
    //     - new_fee_rate
    // Returns
    public entry fun update_fee_tier(
        protocol_authority: &signer, tick_spacing: u64, new_fee_rate: u64
    ) {
        fee_tier::update_fee_tier(protocol_authority, tick_spacing, new_fee_rate);
    }

    // #[cmd]
    // Delete fee_tier.
    // Params
    //     - tick_spacing
    // Returns
    public entry fun delete_fee_tier(
        protocol_authority: &signer, tick_spacing: u64
    ) {
        fee_tier::delete_fee_tier(protocol_authority, tick_spacing);
    }

    // #[cmd]
    // Create a pool of clmmpool protocol. The pool is identified by (CoinTypeA, CoinTypeB, tick_spacing).
    // Params
    //     Type:
    //         - CoinTypeA
    //         - CoinTypeB
    //     - tick_spacing
    //     - initialize_sqrt_price: the init sqrt price of the pool.
    //     - uri: this uri is used for token uri of the position token of this pool.
    // Returns
    public entry fun create_pool(
        account: &signer,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        tick_spacing: u64,
        initialize_sqrt_price: u128,
        uri: String
    ) {
        factory::create_pool(
            account,
            token_a,
            token_b,
            tick_spacing,
            initialize_sqrt_price,
            uri
        );
    }

    // #[cmd]
    // Add liquidity into a pool. The position is identified by the name.
    // The position token is identified by (creator, collection, name), the creator is pool address.
    // Params
    //     Type:
    //         - CoinTypeA
    //         - CoinTypeB
    //     - pool_address
    //     - delta_liquidity
    //     - max_amount_a: the max number of coin_a can be consumed by the pool.
    //     - max_amount_b: the max number of coin_b can be consumed by the pool.
    //     - tick_lower
    //     - tick_upper
    //     - is_open: control whether or not to create a new position or add liquidity on existed position.
    //     - index: position index. if `is_open` is true, index is no use.
    // Returns
    public entry fun add_liquidity(
        account: &signer,
        pool_address: address,
        delta_liquidity: u128,
        max_amount_a: u64,
        max_amount_b: u64,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        index: u64,
    ) {
        // Open position if needed.
        let tick_lower_index = i64::from_u64(tick_lower);
        let tick_upper_index = i64::from_u64(tick_upper);
        let pos_index =
            if (is_open) {
                pool::open_position(account, pool_address, tick_lower_index, tick_upper_index)
            } else {
                pool::check_position_authority(account, pool_address, index);
                let (position_tick_lower, position_tick_upper) = pool::get_position_tick_range(pool_address, index);
                assert!(i64::eq(tick_lower_index, position_tick_lower), EIS_NOT_VALID_TICK);
                assert!(i64::eq(tick_upper_index, position_tick_upper), EIS_NOT_VALID_TICK);
                index
            };

        // Add liquidity
        let receipt = pool::add_liquidity(pool_address, delta_liquidity, pos_index);
        let (amount_a_needed, amount_b_needed) = pool::add_liqudity_pay_amount(&receipt);
        assert!(amount_a_needed <= max_amount_a, EAMOUNT_IN_ABOVE_MAX_LIMIT);
        assert!(amount_b_needed <= max_amount_b, EAMOUNT_IN_ABOVE_MAX_LIMIT);
        let (token_a, token_b) = pool::get_pool_tokens(pool_address);
        let asset_a =
            if (amount_a_needed > 0) {
                primary_fungible_store::withdraw(account, token_a, amount_a_needed)
            } else {
                fungible_asset::zero(token_a)
            };
        let asset_b =
            if (amount_b_needed > 0) {
                primary_fungible_store::withdraw(account, token_b, amount_b_needed)
            } else {
                fungible_asset::zero(token_b)
            };
        pool::repay_add_liquidity(asset_a, asset_b, receipt);
    }

    // #[cmd]
    // 向池子添加流动性（固定代币数量模式）
    // 位置代币通过(creator, collection, name)标识，creator是池子地址
    // 参数：
    //     - CoinTypeA: 代币A类型
    //     - CoinTypeB: 代币B类型
    //     - pool_address: 池子地址
    //     - amount_a: 如果fix_amount_a为false，amount_a是要消费的代币A的最大数量
    //     - amount_b: 如果fix_amount_a为true，amount_b是要消费的代币B的最大数量
    //     - fix_amount_a: 控制固定代币A还是代币B的数量
    //     - tick_lower: 下边界tick
    //     - tick_upper: 上边界tick
    //     - is_open: 控制是否创建新位置或向现有位置添加流动性
    //     - index: 位置索引，如果is_open为true，index无用
    public entry fun add_liquidity_fix_token(
        account: &signer,
        pool_address: address,
        amount_a: u64,
        amount_b: u64,
        fix_amount_a: bool,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        index: u64,
        metadata_a: Object<Metadata>,
        metadata_b: Object<Metadata>
    ) {
        // 如果需要，开启新位置
        let tick_lower_index = i64::from_u64(tick_lower);
        let tick_upper_index = i64::from_u64(tick_upper);
        let pos_index =
            if (is_open) {
                pool::open_position(
                    account,
                    pool_address,
                    tick_lower_index,
                    tick_upper_index
                )
            } else {
                pool::check_position_authority(
                    account, pool_address, index
                );
                let (position_tick_lower, position_tick_upper) =
                    pool::get_position_tick_range(
                        pool_address, index
                    );
                assert!(
                    i64::eq(tick_lower_index, position_tick_lower), EIS_NOT_VALID_TICK
                );
                assert!(
                    i64::eq(tick_upper_index, position_tick_upper), EIS_NOT_VALID_TICK
                );
                index
            };

        // 添加流动性
        let amount = if (fix_amount_a) {
            amount_a
        } else {
            amount_b
        };
        let receipt =
            pool::add_liquidity_fix_coin(
                pool_address, amount, fix_amount_a, pos_index
            );
        let (amount_a_needed, amount_b_needed) = pool::add_liqudity_pay_amount(&receipt);
        if (fix_amount_a) {
            assert!(
                amount_a == amount_a_needed && amount_b_needed <= amount_b,
                EAMOUNT_IN_ABOVE_MAX_LIMIT
            );
        } else {
            assert!(
                amount_b == amount_b_needed && amount_a_needed <= amount_a,
                EAMOUNT_IN_ABOVE_MAX_LIMIT
            );
        };
        let asset_a =
            if (amount_a_needed > 0) {
                primary_fungible_store::withdraw(account, metadata_a, amount_a_needed)
            } else {
                fungible_asset::zero(metadata_a)
            };
        let asset_b =
            if (amount_b_needed > 0) {
                primary_fungible_store::withdraw(account, metadata_b, amount_b_needed)
            } else {
                fungible_asset::zero(metadata_b)
            };
        pool::repay_add_liquidity(asset_a, asset_b, receipt);
    }

    // #[cmd]
    // 从池子中移除流动性
    // 位置代币通过(creator, collection, name)标识，creator是池子地址
    // 参数：
    //     - CoinTypeA: 代币A类型
    //     - CoinTypeB: 代币B类型
    //     - pool_address: 池子地址
    //     - delta_liquidity: 要移除的流动性数量
    //     - min_amount_a: 代币A的最小返回数量
    //     - min_amount_b: 代币B的最小返回数量
    //     - position_index: 要移除流动性的位置索引
    //     - is_close: 如果位置为空，是否关闭位置
    public entry fun remove_liquidity(
        account: &signer,
        pool_address: address,
        delta_liquidity: u128,
        min_amount_a: u64,
        min_amount_b: u64,
        position_index: u64,
        is_close: bool,
    ) {
        // 移除流动性
        let (asset_a, asset_b) =
            pool::remove_liquidity(
                account,
                pool_address,
                delta_liquidity,
                position_index
            );
        let amount_a_returned = fungible_asset::amount(&asset_a);
        let amount_b_returned = fungible_asset::amount(&asset_b);
        assert!(amount_a_returned >= min_amount_a, EAMOUNT_OUT_BELOW_MIN_LIMIT);
        assert!(amount_b_returned >= min_amount_b, EAMOUNT_OUT_BELOW_MIN_LIMIT);

        // 将代币发送给流动性所有者
        let user_address = signer::address_of(account);
        primary_fungible_store::deposit(user_address, asset_a);
        primary_fungible_store::deposit(user_address, asset_b);

        // 收集位置的费用
        let (fee_asset_a, fee_asset_b) =
            pool::collect_fee(
                account, pool_address, position_index, false
            );
        primary_fungible_store::deposit(user_address, fee_asset_a);
        primary_fungible_store::deposit(user_address, fee_asset_b);

        // 如果is_close=true且位置流动性为零，关闭位置
        if (is_close) {
            pool::checked_close_position(
                account, pool_address, position_index
            );
        }
    }

    // #[cmd]
    // 关闭空的位置
    // 参数：
    //     - CoinTypeA: 代币A类型
    //     - CoinTypeB: 代币B类型
    //     - pool_address: 池子地址
    //     - position_index: 位置索引
    public entry fun close_position(
        account: &signer, pool_address: address, position_index: u64
    ) {
        let is_closed =
            pool::checked_close_position(
                account, pool_address, position_index
            );
        if (!is_closed) {
            abort EPOSITION_IS_NOT_ZERO
        };
    }

    // #[cmd]
    // 收集位置获得的费用
    // 参数：
    //     - CoinTypeA: 代币A类型
    //     - CoinTypeB: 代币B类型
    //     - pool_address: 池子地址
    //     - position_index: 位置索引
    public entry fun collect_fee(
        account: &signer, pool_address: address, position_index: u64
    ) {
        let user_address = signer::address_of(account);
        let (fee_asset_a, fee_asset_b) =
            pool::collect_fee(
                account, pool_address, position_index, true
            );
        primary_fungible_store::deposit(user_address, fee_asset_a);
        primary_fungible_store::deposit(user_address, fee_asset_b);
    }

    // #[cmd]
    // 收集位置获得的奖励
    // 参数：
    //     - CoinTypeA: 代币A类型
    //     - CoinTypeB: 代币B类型
    //     - CoinTypeC: 奖励代币类型
    //     - pool_address: 池子地址
    //     - rewarder_index: 奖励器索引(0,1,2)
    //     - pos_index: 收集奖励的位置索引
    public entry fun collect_rewarder(
        account: &signer,
        pool_address: address,
        rewarder_index: u8,
        pos_index: u64
    ) {
        let user_address = signer::address_of(account);
        let rewarder_asset =
            pool::collect_rewarder(
                account,
                pool_address,
                pos_index,
                rewarder_index,
                true
            );
        primary_fungible_store::deposit(user_address, rewarder_asset);
    }

    // #[cmd]
    // 为协议费用收集权限收集协议费用
    // 参数：
    //     - CoinTypeA: 代币A类型
    //     - CoinTypeB: 代币B类型
    //     - account: 协议费用收集权限账户
    //     - pool_address: 池子地址
    public entry fun collect_protocol_fee(
        account: &signer, pool_address: address
    ) {
        let addr = signer::address_of(account);
        let (asset_a, asset_b) =
            pool::collect_protocol_fee(account, pool_address);
        primary_fungible_store::deposit(addr, asset_a);
        primary_fungible_store::deposit(addr, asset_b);
    }

    // #[cmd]
    // 交换代币
    // 参数：
    //     - account: 交换交易签名者
    //     - pool_address: 池子地址
    //     - a_to_b: true表示A换B；false表示B换A
    //     - by_amount_in: 表示amount是输入数量（如果a_to_b为true，则输入是代币A）还是输出数量
    //     - amount: 交换数量
    //     - amount_limit: 如果by_amount_in为true，amount_limit是最小输出数量；
    //                     如果by_amount_in为false，amount_limit是最大输入数量
    //     - sqrt_price_limit: 价格限制
    //     - partner: 合作伙伴名称
    public entry fun swap(
        account: &signer,
        pool_address: address,
        a_to_b: bool,
        by_amount_in: bool,
        amount: u64,
        amount_limit: u64,
        sqrt_price_limit: u128,
        partner: String,
        metadata_a: Object<Metadata>,
        metadata_b: Object<Metadata>
    ) {
        let swap_from = signer::address_of(account);
        let (asset_a, asset_b, flash_receipt) =
            pool::flash_swap(
                pool_address,
                swap_from,
                partner,
                a_to_b,
                by_amount_in,
                amount,
                sqrt_price_limit
            );
        let in_amount = pool::swap_pay_amount(&flash_receipt);
        let out_amount =
            if (a_to_b) {
                fungible_asset::amount(&asset_b)
            } else {
                fungible_asset::amount(&asset_a)
            };

        // 检查限制
        if (by_amount_in) {
            assert!(in_amount == amount, ESWAP_AMOUNT_INCORRECT);
            assert!(out_amount >= amount_limit, EAMOUNT_OUT_BELOW_MIN_LIMIT);
        } else {
            assert!(out_amount == amount, ESWAP_AMOUNT_INCORRECT);
            assert!(in_amount <= amount_limit, EAMOUNT_IN_ABOVE_MAX_LIMIT)
        };

        // 偿还代币
        if (a_to_b) {
            fungible_asset::destroy_zero(asset_a);
            primary_fungible_store::deposit(swap_from, asset_b);
            let payment_asset_a = primary_fungible_store::withdraw(account, metadata_a, in_amount);
            pool::repay_flash_swap(
                payment_asset_a,
                fungible_asset::zero(metadata_b),
                flash_receipt
            );
        } else {
            fungible_asset::destroy_zero(asset_b);
            primary_fungible_store::deposit(swap_from, asset_a);
            let payment_asset_b = primary_fungible_store::withdraw(account, metadata_b, in_amount);
            pool::repay_flash_swap(
                fungible_asset::zero(metadata_a),
                payment_asset_b,
                flash_receipt
            );
        }
    }

    // #[cmd]
    // 为协议权限更新池子费率
    // 参数：
    //     - protocol_authority: 协议权限账户
    //     - pool_addr: 池子地址
    //     - new_fee_rate: 新的费率
    public entry fun update_fee_rate(
        protocol_authority: &signer, pool_addr: address, new_fee_rate: u64
    ) {
        pool::update_fee_rate(protocol_authority, pool_addr, new_fee_rate);
    }

    // #[cmd]
    // 初始化奖励器
    // 参数：
    //     - account: 协议权限签名者
    //     - pool_address: 池子地址
    //     - authority: 奖励器权限地址
    //     - index: 奖励器索引
    public entry fun initialize_rewarder(
        account: &signer,
        pool_address: address,
        authority: address,
        index: u64,
        reward_token: Object<Metadata>,
    ) {
        pool::initialize_rewarder(account, pool_address, authority, index, reward_token);
    }

    // #[cmd]
    // 更新奖励器发放速率
    // 参数：
    //     - pool_address: 池子地址
    //     - index: 奖励器索引
    //     - emission_per_second: 每秒发放数量
    public entry fun update_rewarder_emission(
        account: &signer,
        pool_address: address,
        index: u8,
        emission_per_second: u128,
        reward_token: Object<Metadata>,
    ) {
        pool::update_emission(
            account,
            pool_address,
            index,
            emission_per_second,
            reward_token
        );
    }

    // #[cmd]
    // 转移奖励器权限
    // 参数：
    //     - pool_address: 池子地址
    //     - index: 奖励器索引
    //     - new_authority: 新权限地址
    public entry fun transfer_rewarder_authority(
        account: &signer,
        pool_addr: address,
        index: u8,
        new_authority: address
    ) {
        pool::transfer_rewarder_authority(
            account, pool_addr, index, new_authority
        );
    }

    // #[cmd]
    // 接受奖励器权限
    // 参数：
    //     - pool_address: 池子地址
    //     - index: 奖励器索引
    public entry fun accept_rewarder_authority(
        account: &signer, pool_addr: address, index: u8
    ) {
        pool::accept_rewarder_authority(account, pool_addr, index);
    }

    // #[cmd]
    // 创建合作伙伴
    // 合作伙伴通过名称标识
    // 参数：
    //     - fee_rate: 费率
    //     - name: 合作伙伴名称
    //     - receiver: 合作伙伴权限地址，用于领取费用
    //     - start_time: 合作伙伴有效开始时间
    //     - end_time: 合作伙伴有效结束时间
    public entry fun create_partner(
        account: &signer,
        name: String,
        fee_rate: u64,
        receiver: address,
        start_time: u64,
        end_time: u64
    ) {
        partner::create_partner(
            account,
            name,
            fee_rate,
            receiver,
            start_time,
            end_time
        );
    }

    // #[cmd]
    // 更新合作伙伴费率
    // 参数：
    //     - name: 合作伙伴名称
    //     - new_fee_rate: 新费率
    public entry fun update_partner_fee_rate(
        protocol_authority: &signer, name: String, new_fee_rate: u64
    ) {
        partner::update_fee_rate(protocol_authority, name, new_fee_rate);
    }

    // #[cmd]
    // 更新合作伙伴时间
    // 参数：
    //     - name: 合作伙伴名称
    //     - start_time: 开始时间
    //     - end_time: 结束时间
    public entry fun update_partner_time(
        protocol_authority: &signer,
        name: String,
        start_time: u64,
        end_time: u64
    ) {
        partner::update_time(protocol_authority, name, start_time, end_time);
    }

    // #[cmd]
    // 转移合作伙伴接收者
    // 参数：
    //     - name: 合作伙伴名称
    //     - new_receiver: 新接收者地址
    public entry fun transfer_partner_receiver(
        account: &signer, name: String, new_recevier: address
    ) {
        partner::transfer_receiver(account, name, new_recevier);
    }

    // #[cmd]
    // 接受合作伙伴接收者
    // 参数：
    //     - name: 合作伙伴名称
    public entry fun accept_partner_receiver(
        account: &signer, name: String
    ) {
        partner::accept_receiver(account, name);
    }

    // #[cmd]
    // 暂停协议
    public entry fun pause(protocol_authority: &signer) {
        config::pause(protocol_authority);
    }

    // #[cmd]
    // 恢复协议
    public entry fun unpause(protocol_authority: &signer) {
        config::unpause(protocol_authority);
    }

    // #[cmd]
    // 暂停池子
    // 参数：
    //     - pool_address: 池子地址
    public entry fun pause_pool(
        protocol_authority: &signer, pool_address: address
    ) {
        pool::pause(protocol_authority, pool_address);
    }

    // #[cmd]
    // 恢复池子
    // 参数：
    //     - pool_address: 池子地址
    public entry fun unpause_pool(
        protocol_authority: &signer, pool_address: address
    ) {
        pool::unpause(protocol_authority, pool_address);
    }

    // #[cmd]
    // 申请合作伙伴推荐费用
    // 参数：
    //     - account: 合作伙伴接收者账户签名者
    //     - name: 合作伙伴名称
    public entry fun claim_ref_fee(
        account: &signer,
        name: String,
        token: Object<Metadata>
    ) {
        partner::claim_ref_fee(account, name, token)
    }

    // #[cmd]
    // 初始化集中流动性访问控制列表
    // 参数：
    //    - account: 集中流动性池部署者
    public entry fun init_clmm_acl(account: &signer) {
        config::init_clmm_acl(account)
    }

    // #[cmd]
    // 更新池子的位置NFT集合和代币URI
    // 参数：
    //     - account: 设置者账户签名者
    //     - pool_address: 池子地址
    //     - uri: NFT URI
    public entry fun update_pool_uri(
        account: &signer, pool_address: address, uri: String
    ) {
        pool::update_pool_uri(account, pool_address, uri)
    }

    // #[cmd]
    // 在集中流动性访问控制列表中添加角色
    // 参数：
    //     - account: 协议权限签名者
    //     - member: 角色成员地址
    //     - role: 角色
    public entry fun add_role(account: &signer, member: address, role: u8) {
        config::add_role(account, member, role)
    }

    // #[cmd]
    // 从集中流动性访问控制列表中移除角色
    // 参数：
    //     - account: 协议权限签名者
    //     - member: 角色成员地址
    //     - role: 角色
    public entry fun remove_role(
        account: &signer, member: address, role: u8
    ) {
        config::remove_role(account, member, role)
    }
}
