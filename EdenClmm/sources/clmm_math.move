/// CLMM数学计算模块
/// 该模块包含集中流动性做市商(CLMM)的核心数学计算功能
/// 包括流动性计算、价格变化计算、代币数量计算等关键算法
/// 类似于Uniswap V3的数学计算库
module eden_clmm::clmm_math {
    use integer_mate::full_math_u128;
    use integer_mate::full_math_u64;
    use integer_mate::i64::{Self, I64};
    use eden_clmm::tick_math;
    use integer_mate::math_u128;
    use integer_mate::math_u256::{Self};

    // 错误代码
    const ETOKEN_AMOUNT_MAX_EXCEEDED: u64 = 1;
    // 代币数量超过最大值
    const ETOKEN_AMOUNT_MIN_SUBCEEDED: u64 = 2;
    // 代币数量低于最小值
    const EMULTIPLICATION_OVERFLOW: u64 = 3;
    // 乘法溢出
    const EINTEGER_DOWNCAST_OVERFLOW: u64 = 4;
    // 整数向下转换溢出
    const EINVALID_SQRT_PRICE_INPUT: u64 = 5;
    // 无效的sqrt价格输入
    const EINVALID_FIXED_TOKEN_TYPE: u64 = 6;
    // 无效的固定代币类型
    const EFUN_DEPRECATED: u64 = 7; // 函数已弃用

    // 费率分母常量
    const FEE_RATE_DENOMINATOR: u64 = 1000000;

    // 获取费率分母
    // 返回值：费率分母
    public fun fee_rate_denominator(): u64 {
        FEE_RATE_DENOMINATOR
    }

    // 根据代币A数量计算流动性
    // 参数：
    //     - sqrt_price_0: 起始sqrt价格
    //     - sqrt_price_1: 结束sqrt价格
    //     - amount_a: 代币A数量
    //     - round_up: 是否向上取整
    // 返回值：流动性值
    public fun get_liquidity_from_a(
        sqrt_price_0: u128,
        sqrt_price_1: u128,
        amount_a: u64,
        round_up: bool
    ): u128 {
        let sqrt_price_diff =
            if (sqrt_price_0 > sqrt_price_1) {
                sqrt_price_0 - sqrt_price_1
            } else {
                sqrt_price_1 - sqrt_price_0
            };
        // 计算分子：sqrt_price_0 * sqrt_price_1 * amount_a
        let numberator =
            (full_math_u128::full_mul_v2(sqrt_price_0, sqrt_price_1) >> 64)
                * (amount_a as u256);
        let div_res = math_u256::div_round(
            numberator, (sqrt_price_diff as u256), round_up
        );
        (div_res as u128)
    }

    // 根据代币B数量计算流动性
    // 参数：
    //     - sqrt_price_0: 起始sqrt价格
    //     - sqrt_price_1: 结束sqrt价格
    //     - amount_b: 代币B数量
    //     - round_up: 是否向上取整
    // 返回值：流动性值
    public fun get_liquidity_from_b(
        sqrt_price_0: u128,
        sqrt_price_1: u128,
        amount_b: u64,
        round_up: bool
    ): u128 {
        let sqrt_price_diff =
            if (sqrt_price_0 > sqrt_price_1) {
                sqrt_price_0 - sqrt_price_1
            } else {
                sqrt_price_1 - sqrt_price_0
            };
        // 计算：(amount_b << 64) / sqrt_price_diff
        let div_res =
            math_u256::div_round(
                ((amount_b as u256) << 64),
                (sqrt_price_diff as u256),
                round_up
            );
        (div_res as u128)
    }

    // 计算代币A的数量变化
    // 参数：
    //     - sqrt_price_0: 起始sqrt价格
    //     - sqrt_price_1: 结束sqrt价格
    //     - liquidity: 流动性
    //     - round_up: 是否向上取整
    // 返回值：代币A的数量变化
    public fun get_delta_a(
        sqrt_price_0: u128,
        sqrt_price_1: u128,
        liquidity: u128,
        round_up: bool
    ): u64 {
        let sqrt_price_diff =
            if (sqrt_price_0 > sqrt_price_1) {
                sqrt_price_0 - sqrt_price_1
            } else {
                sqrt_price_1 - sqrt_price_0
            };
        if (sqrt_price_diff == 0 || liquidity == 0) {
            return 0
        };
        // 计算：(liquidity * sqrt_price_diff << 64) / (sqrt_price_0 * sqrt_price_1)
        let (numberator, overflowing) =
            math_u256::checked_shlw(
                full_math_u128::full_mul_v2(liquidity, sqrt_price_diff)
            );
        if (overflowing) {
            abort EMULTIPLICATION_OVERFLOW
        };
        let denominator = full_math_u128::full_mul_v2(sqrt_price_0, sqrt_price_1);
        let quotient = math_u256::div_round(numberator, denominator, round_up);
        (quotient as u64)
    }

    // 计算代币B的数量变化
    // 参数：
    //     - sqrt_price_0: 起始sqrt价格
    //     - sqrt_price_1: 结束sqrt价格
    //     - liquidity: 流动性
    //     - round_up: 是否向上取整
    // 返回值：代币B的数量变化
    public fun get_delta_b(
        sqrt_price_0: u128,
        sqrt_price_1: u128,
        liquidity: u128,
        round_up: bool
    ): u64 {
        let sqrt_price_diff =
            if (sqrt_price_0 > sqrt_price_1) {
                sqrt_price_0 - sqrt_price_1
            } else {
                sqrt_price_1 - sqrt_price_0
            };
        if (sqrt_price_diff == 0 || liquidity == 0) {
            return 0
        };
        // 计算：(liquidity * sqrt_price_diff) >> 64
        let lo64_mask =
            0x000000000000000000000000000000000000000000000000ffffffffffffffff;
        let product = full_math_u128::full_mul_v2(liquidity, sqrt_price_diff);
        let should_round_up = (round_up) && ((product & lo64_mask) > 0);
        if (should_round_up) {
            return (((product >> 64) + 1) as u64)
        };
        ((product >> 64) as u64)
    }

    // 根据代币A数量计算下一个sqrt价格（向上）
    // 参数：
    //     - sqrt_price: 当前sqrt价格
    //     - liquidity: 流动性
    //     - amount: 代币A数量
    //     - by_amount_input: 是否按输入数量计算
    // 返回值：下一个sqrt价格
    public fun get_next_sqrt_price_a_up(
        sqrt_price: u128,
        liquidity: u128,
        amount: u64,
        by_amount_input: bool
    ): u128 {
        if (amount == 0) {
            return sqrt_price
        };
        // 计算新的sqrt价格
        let (numberator, overflowing) =
            math_u256::checked_shlw(full_math_u128::full_mul_v2(sqrt_price, liquidity));
        if (overflowing) {
            abort EMULTIPLICATION_OVERFLOW
        };

        let liquidity_shl_64 = (liquidity as u256) << 64;
        let product = full_math_u128::full_mul_v2(sqrt_price, (amount as u128));
        let new_sqrt_price =
            if (by_amount_input) {
                math_u256::div_round(numberator, (liquidity_shl_64 + product), true) as u128
            } else {
                math_u256::div_round(numberator, (liquidity_shl_64 - product), true) as u128
            };

        if (new_sqrt_price > tick_math::max_sqrt_price()) {
            abort ETOKEN_AMOUNT_MAX_EXCEEDED
        } else if (new_sqrt_price < tick_math::min_sqrt_price()) {
            abort ETOKEN_AMOUNT_MIN_SUBCEEDED
        };

        new_sqrt_price
    }

    // 根据代币B数量计算下一个sqrt价格（向下）
    // 参数：
    //     - sqrt_price: 当前sqrt价格
    //     - liquidity: 流动性
    //     - amount: 代币B数量
    //     - by_amount_input: 是否按输入数量计算
    // 返回值：下一个sqrt价格
    public fun get_next_sqrt_price_b_down(
        sqrt_price: u128,
        liquidity: u128,
        amount: u64,
        by_amount_input: bool
    ): u128 {
        // 计算delta_sqrt_price：(amount << 64) / liquidity
        let delta_sqrt_price = math_u128::checked_div_round(((amount as u128) << 64), liquidity, !by_amount_input);
        let new_sqrt_price =
            if (by_amount_input) {
                sqrt_price + delta_sqrt_price
            } else {
                sqrt_price - delta_sqrt_price
            };

        if (new_sqrt_price > tick_math::max_sqrt_price()) {
            abort ETOKEN_AMOUNT_MAX_EXCEEDED
        } else if (new_sqrt_price < tick_math::min_sqrt_price()) {
            abort ETOKEN_AMOUNT_MIN_SUBCEEDED
        };

        new_sqrt_price
    }

    // 根据输入数量计算下一个sqrt价格
    // 参数：
    //     - sqrt_price: 当前sqrt价格
    //     - liquidity: 流动性
    //     - amount: 输入数量
    //     - a_to_b: 是否从A到B的交换
    // 返回值：下一个sqrt价格
    public fun get_next_sqrt_price_from_input(
        sqrt_price: u128,
        liquidity: u128,
        amount: u64,
        a_to_b: bool
    ): u128 {
        if (a_to_b) {
            get_next_sqrt_price_a_up(sqrt_price, liquidity, amount, true)
        } else {
            get_next_sqrt_price_b_down(sqrt_price, liquidity, amount, true)
        }
    }

    // 根据输出数量计算下一个sqrt价格
    // 参数：
    //     - sqrt_price: 当前sqrt价格
    //     - liquidity: 流动性
    //     - amount: 输出数量
    //     - a_to_b: 是否从A到B的交换
    // 返回值：下一个sqrt价格
    public fun get_next_sqrt_price_from_output(
        sqrt_price: u128,
        liquidity: u128,
        amount: u64,
        a_to_b: bool
    ): u128 {
        if (a_to_b) {
            get_next_sqrt_price_b_down(sqrt_price, liquidity, amount, false)
        } else {
            get_next_sqrt_price_a_up(sqrt_price, liquidity, amount, false)
        }
    }

    // 根据输入计算上方delta值（版本2）
    // 参数：
    //     - current_sqrt_price: 当前sqrt价格
    //     - target_sqrt_price: 目标sqrt价格
    //     - liquidity: 流动性
    //     - a_to_b: 是否从A到B的交换
    // 返回值：delta值
    public fun get_delta_up_from_input_v2(
        current_sqrt_price: u128,
        target_sqrt_price: u128,
        liquidity: u128,
        a_to_b: bool
    ): u256 {
        let sqrt_price_diff =
            if (current_sqrt_price > target_sqrt_price) {
                current_sqrt_price - target_sqrt_price
            } else {
                target_sqrt_price - current_sqrt_price
            };
        if (sqrt_price_diff == 0 || liquidity == 0) {
            return 0
        };
        if (a_to_b) {
            // A到B交换：计算代币A的数量
            let (numberator, overflowing) =
                math_u256::checked_shlw(full_math_u128::full_mul_v2(liquidity, sqrt_price_diff));
            if (overflowing) {
                abort EMULTIPLICATION_OVERFLOW
            };
            let denominator = full_math_u128::full_mul_v2(current_sqrt_price, target_sqrt_price);
            math_u256::div_round(numberator, denominator, true)
        } else {
            // B到A交换：计算代币B的数量
            let product = full_math_u128::full_mul_v2(liquidity, sqrt_price_diff);
            let lo64_mask = 0x000000000000000000000000000000000000000000000000ffffffffffffffff;
            let should_round_up = (product & lo64_mask) > 0;
            if (should_round_up) {
                return (product >> 64) + 1
            };
            product >> 64
        }
    }


    // 根据输出计算下方delta值（版本2）
    // 参数：
    //     - current_sqrt_price: 当前sqrt价格
    //     - target_sqrt_price: 目标sqrt价格
    //     - liquidity: 流动性
    //     - a_to_b: 是否从A到B的交换
    // 返回值：delta值
    public fun get_delta_down_from_output_v2(
        current_sqrt_price: u128,
        target_sqrt_price: u128,
        liquidity: u128,
        a_to_b: bool
    ): u256 {
        let sqrt_price_diff =
            if (current_sqrt_price > target_sqrt_price) {
                current_sqrt_price - target_sqrt_price
            } else {
                target_sqrt_price - current_sqrt_price
            };
        if (sqrt_price_diff == 0 || liquidity == 0) {
            return 0
        };
        if (a_to_b) {
            // A到B交换：计算代币B的数量
            let product = full_math_u128::full_mul_v2(liquidity, sqrt_price_diff);
            product >> 64
        } else {
            // B到A交换：计算代币A的数量
            let (numberator, overflowing) =
                math_u256::checked_shlw(
                    full_math_u128::full_mul_v2(liquidity, sqrt_price_diff)
                );
            if (overflowing) {
                abort EMULTIPLICATION_OVERFLOW
            };
            let denominator = full_math_u128::full_mul_v2(current_sqrt_price, target_sqrt_price);
            math_u256::div_round(numberator, denominator, false)
        }
    }

    // 计算交换步骤
    // 参数：
    //     - current_sqrt_price: 当前sqrt价格
    //     - target_sqrt_price: 目标sqrt价格
    //     - liquidity: 流动性
    //     - amount: 交换数量
    //     - fee_rate: 费率
    //     - a2b: 是否从A到B的交换
    //     - by_amount_in: 是否按输入数量计算
    // 返回值：(输入数量, 输出数量, 下一个sqrt价格, 费用数量)
    public fun compute_swap_step(
        current_sqrt_price: u128,
        target_sqrt_price: u128,
        liquidity: u128,
        amount: u64,
        fee_rate: u64,
        a2b: bool,
        by_amount_in: bool
    ): (u64, u64, u128, u64) {
        let next_sqrt_price = target_sqrt_price;
        let amount_in: u64 = 0;
        let amount_out: u64 = 0;
        let fee_amount: u64 = 0;
        if (liquidity == 0) {
            return (amount_in, amount_out, next_sqrt_price, fee_amount)
        };
        if (a2b) {
            assert!(current_sqrt_price >= target_sqrt_price, EINVALID_SQRT_PRICE_INPUT)
        } else {
            assert!(current_sqrt_price < target_sqrt_price, EINVALID_SQRT_PRICE_INPUT)
        };

        if (by_amount_in) {
            // 按输入数量计算
            let amount_remain =
                full_math_u64::mul_div_floor(
                    amount, (FEE_RATE_DENOMINATOR - fee_rate), FEE_RATE_DENOMINATOR
                );
            let max_amount_in =
                get_delta_up_from_input_v2(
                    current_sqrt_price,
                    target_sqrt_price,
                    liquidity,
                    a2b
                );
            if (max_amount_in > (amount_remain as u256)) {
                amount_in = amount_remain;
                fee_amount = amount - amount_remain;
                next_sqrt_price = get_next_sqrt_price_from_input(
                    current_sqrt_price,
                    liquidity,
                    amount_remain,
                    a2b
                );
            } else {
                // 这里不会溢出，因为max_amount_in < amount_remain且amount_remain是u64类型
                amount_in = (max_amount_in as u64);
                fee_amount = full_math_u64::mul_div_ceil(
                    amount_in, fee_rate, (FEE_RATE_DENOMINATOR - fee_rate)
                );
                next_sqrt_price = target_sqrt_price;
            };
            amount_out =
                (
                    get_delta_down_from_output_v2(
                        current_sqrt_price,
                        next_sqrt_price,
                        liquidity,
                        a2b
                    ) as u64
                );
        } else {
            // 按输出数量计算
            let max_amount_out =
                get_delta_down_from_output_v2(
                    current_sqrt_price,
                    target_sqrt_price,
                    liquidity,
                    a2b
                );
            if (max_amount_out > (amount as u256)) {
                amount_out = amount;
                next_sqrt_price = get_next_sqrt_price_from_output(
                    current_sqrt_price, liquidity, amount, a2b
                );
            } else {
                amount_out = (max_amount_out as u64);
                next_sqrt_price = target_sqrt_price;
            };
            amount_in =
                (
                    get_delta_up_from_input_v2(
                        current_sqrt_price,
                        next_sqrt_price,
                        liquidity,
                        a2b
                    ) as u64
                );
            fee_amount = full_math_u64::mul_div_ceil(
                amount_in, fee_rate, (FEE_RATE_DENOMINATOR - fee_rate)
            );
        };

        (amount_in, amount_out, next_sqrt_price, fee_amount)
    }

    // 根据流动性计算代币数量
    // 参数：
    //     - tick_lower: 流动性的下边界tick
    //     - tick_upper: 流动性的上边界tick
    //     - current_tick_index: 当前tick索引
    //     - current_sqrt_price: 当前sqrt价格
    //     - liquidity: 流动性
    //     - round_up: 是否向上取整
    // 返回值：(代币A数量, 代币B数量)
    public fun get_amount_by_liquidity(
        tick_lower: I64,
        tick_upper: I64,
        current_tick_index: I64,
        current_sqrt_price: u128,
        liquidity: u128,
        round_up: bool
    ): (u64, u64) {
        if (liquidity == 0) {
            return (0, 0)
        };
        let lower_price = tick_math::get_sqrt_price_at_tick(tick_lower);
        let upper_price = tick_math::get_sqrt_price_at_tick(tick_upper);

        let (amount_a, amount_b) =
            if (i64::lt(current_tick_index, tick_lower)) {
                // 仅代币A
                (get_delta_a(lower_price, upper_price, liquidity, round_up), 0)
            } else if (i64::lt(current_tick_index, tick_upper)) {
                // 代币A和B都有
                (
                    get_delta_a(
                        current_sqrt_price,
                        upper_price,
                        liquidity,
                        round_up
                    ),
                    get_delta_b(
                        lower_price,
                        current_sqrt_price,
                        liquidity,
                        round_up
                    )
                )
            } else {
                // 仅代币B
                (0, get_delta_b(lower_price, upper_price, liquidity, round_up))
            };
        (amount_a, amount_b)
    }

    // 根据数量计算流动性
    // 参数：
    //     - lower_index: 下边界tick索引
    //     - upper_index: 上边界tick索引
    //     - current_tick_index: 当前tick索引
    //     - current_sqrt_price: 当前sqrt价格
    //     - amount: 代币数量
    //     - is_fixed_a: 是否固定代币A
    // 返回值：(流动性, 代币A数量, 代币B数量)
    public fun get_liquidity_from_amount(
        lower_index: I64,
        upper_index: I64,
        current_tick_index: I64,
        current_sqrt_price: u128,
        amount: u64,
        is_fixed_a: bool
    ): (u128, u64, u64) {
        let lower_price = tick_math::get_sqrt_price_at_tick(lower_index);
        let upper_price = tick_math::get_sqrt_price_at_tick(upper_index);
        let amount_a: u64 = 0;
        let amount_b: u64 = 0;
        let _liquidity: u128 = 0;
        if (is_fixed_a) {
            // 固定代币A数量
            amount_a = amount;
            if (i64::lt(current_tick_index, lower_index)) {
                _liquidity = get_liquidity_from_a(lower_price, upper_price, amount, false);
            } else if (i64::lt(current_tick_index, upper_index)) {
                _liquidity = get_liquidity_from_a(
                    current_sqrt_price, upper_price, amount, false
                );
                amount_b = get_delta_b(
                    current_sqrt_price,
                    lower_price,
                    _liquidity,
                    true
                );
            } else {
                abort EINVALID_FIXED_TOKEN_TYPE
            };
        } else {
            // 固定代币B数量
            amount_b = amount;
            if (i64::gte(current_tick_index, upper_index)) {
                _liquidity = get_liquidity_from_b(lower_price, upper_price, amount, false);
            } else if (i64::gte(current_tick_index, lower_index)) {
                _liquidity = get_liquidity_from_b(
                    lower_price, current_sqrt_price, amount, false
                );
                amount_a = get_delta_a(
                    current_sqrt_price,
                    upper_price,
                    _liquidity,
                    true
                );
            } else {
                abort EINVALID_FIXED_TOKEN_TYPE
            }
        };
        (_liquidity, amount_a, amount_b)
    }

    #[test]
    fun test_get_liquidity_from_a() {
        use integer_mate::i64;
        //18446744073709551616 19392480388906836277 1000000 20505166
        let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i64::from(0));
        let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i64::from(1000));
        let amount_a = 1000000;
        assert!(
            get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false) == 20505166,
            0
        );

        //11188795550323325955 30412779051191548722 1000000000 959569283
        let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i64::neg_from(10000));
        let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i64::from(10000));
        let amount_a = 1000000000;
        assert!(
            get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false) == 959569283,
            0
        );

        //18437523468038800957 18455969290605290427 300000000000 300014987250637
        let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i64::neg_from(10));
        let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i64::from(10));
        let amount_a = 300000000000;
        assert!(
            get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false)
                == 300014987250637,
            0
        );

        // 18437523468038800957 19392480388906836277 300000000000 6089108304263
        let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i64::neg_from(10));
        let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i64::from(1000));
        let amount_a = 300000000000;
        assert!(
            get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false)
                == 6089108304263,
            0
        );

        //18437523468038800957 18455969290605290427 999000000000000 999049907544623895
        let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i64::neg_from(10));
        let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i64::from(10));
        let amount_a = 999000000000000;
        assert!(
            get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false)
                == 999049907544623895,
            0
        );

        //18437523468038800957 18455969290605290427 18446744073709551615 18447665626965832135371
        let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i64::neg_from(10));
        let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i64::from(10));
        let amount_a = 18446744073709551615;
        assert!(
            get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false)
                == 18447665626965832135371,
            0
        );
    }

    #[test]
    fun test_get_liquidity_from_b() {
        use integer_mate::i64;
        // 18446744073709551616 19392480388906836277 1000000 19505166
        let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i64::from(0));
        let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i64::from(1000));
        let amount_b = 1000000;
        assert!(
            get_liquidity_from_b(sqrt_price_0, sqrt_price_1, amount_b, false) == 19505166,
            0
        );

        // 11188795550323325955 30412779051191548722 1000000000 959569283
        let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i64::neg_from(10000));
        let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i64::from(10000));
        let amount_b = 1000000000;
        assert!(
            get_liquidity_from_b(sqrt_price_0, sqrt_price_1, amount_b, false) == 959569283,
            0
        );

        // 18437523468038800957 18455969290605290427 300000000000 300014987250637
        let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i64::neg_from(10));
        let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i64::from(10));
        let amount_b = 300000000000;
        assert!(
            get_liquidity_from_b(sqrt_price_0, sqrt_price_1, amount_b, false)
                == 300014987250637,
            0
        );

        // 18437523468038800957 19392480388906836277 300000000000 5795050123394
        let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i64::neg_from(10));
        let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i64::from(1000));
        let amount_b = 300000000000;
        assert!(
            get_liquidity_from_b(sqrt_price_0, sqrt_price_1, amount_b, false)
                == 5795050123394,
            0
        );

        // 18437523468038800957 19392480388906836277 18446744073709551615 356332688401932418314
        let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i64::neg_from(10));
        let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i64::from(1000));
        let amount_b = 18446744073709551615;
        assert!(
            get_liquidity_from_b(sqrt_price_0, sqrt_price_1, amount_b, false)
                == 356332688401932418314,
            0
        );
    }

    #[test]
    fun test_get_delta_a() {
        assert!(
            get_delta_a(4u128 << 64, 2u128 << 64, 4, true) == 1,
            0
        );
        assert!(
            get_delta_a(4u128 << 64, 2u128 << 64, 4, false) == 1,
            0
        );

        assert!(get_delta_a(4 << 64, 4 << 64, 4, true) == 0, 0);
        assert!(get_delta_a(4 << 64, 4 << 64, 4, false) == 0, 0);
    }

    #[test]
    fun test_get_delta_b() {
        assert!(
            get_delta_b(4u128 << 64, 2u128 << 64, 4, true) == 8,
            0
        );
        assert!(
            get_delta_b(4u128 << 64, 2u128 << 64, 4, false) == 8,
            0
        );

        assert!(get_delta_b(4 << 64, 4 << 64, 4, true) == 0, 0);
        assert!(get_delta_b(4 << 64, 4 << 64, 4, false) == 0, 0);
    }

    #[test]
    fun test_get_next_price_a_up() {
        let (sqrt_price, liquidity, amount) = (10u128 << 64, 200u128 << 64, 10000000u64);
        let r1 = get_next_sqrt_price_a_up(sqrt_price, liquidity, amount, true);
        let r2 = get_next_sqrt_price_a_up(sqrt_price, liquidity, amount, false);
        assert!(184467440737090516161u128 == r1, 0);
        assert!(184467440737100516161u128 == r2, 0);
    }

    #[test]
    fun test_get_next_price_b_down() {
        let (sqrt_price, liquidity, amount, add) =
            (
                62058032627749460283664515388u128,
                56315830353026631512438212669420532741u128,
                10476203047244913035u64,
                true
            );
        let r = get_next_sqrt_price_b_down(sqrt_price, liquidity, amount, add);
        assert!(62058032627749460283664515391u128 == r, 0);
    }

    #[test]
    fun test_compute_swap_step() {
        let (current_sqrt_price, target_sqrt_price, liquidity, amount, fee_rate) =
            (1u128 << 64, 2u128 << 64, 1000u128 << 32, 20000, 1000u64);
        let (amount_in, amount_out, next_sqrt_price, fee_amount) =
            compute_swap_step(
                current_sqrt_price,
                target_sqrt_price,
                liquidity,
                amount,
                fee_rate,
                false,
                false
            );
        // 20001 20000 18446744159608897937 21
        assert!(amount_in == 20001, 0);
        assert!(amount_out == 20000, 0);
        assert!(next_sqrt_price == 18446744159608897937, 0);
        assert!(fee_amount == 21, 0);

        // 19980 19979 18446744159522998190 20
        let (amount_in, amount_out, next_sqrt_price, fee_amount) =
            compute_swap_step(
                current_sqrt_price,
                target_sqrt_price,
                liquidity,
                amount,
                fee_rate,
                false,
                true
            );
        assert!(amount_in == 19980, 0);
        assert!(amount_out == 19979, 0);
        assert!(next_sqrt_price == 18446744159522998190, 0);
        assert!(fee_amount == 20, 0);
    }
}
