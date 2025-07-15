/// Tick价格数学计算模块
/// 该模块提供了tick索引和sqrt价格之间的转换功能
/// 类似于Uniswap V3的tick数学运算，用于集中流动性管理
module eden_clmm::tick_math {
    use eden_clmm::config;
    use integer_mate::full_math_u128;
    use integer_mate::i64::{Self, I64};
    use integer_mate::i128;
    #[test_only]
    use aptos_std::debug::print;
    #[test_only]
    use aptos_std::string_utils;


    // 常量定义
    const TICK_BOUND: u64 = 1109090;
    // tick边界值
    const MAX_SQRT_PRICE_X64: u128 = 79226673515401279992447579055;
    // 最大sqrt价格（64位定点数）
    const MIN_SQRT_PRICE_X64: u128 = 4295048016; // 最小sqrt价格（64位定点数）

    // 错误代码
    const EINVALID_TICK: u64 = 1;
    // 无效的tick
    const EINVALID_SQRT_PRICE: u64 = 2; // 无效的sqrt价格

    // 返回最大sqrt价格
    // 返回值：最大sqrt价格值
    public fun max_fifrt_price(): u128 {
        MAX_SQRT_PRICE_X64
    }

    // 返回最小sqrt价格
    // 返回值：最小sqrt价格值
    public fun min_fifrt_price(): u128 {
        MIN_SQRT_PRICE_X64
    }

    // 返回最大tick值
    // 返回值：最大tick值
    public fun max_tick(): i64::I64 {
        i64::from(TICK_BOUND)
    }

    // 返回最小tick值
    // 返回值：最小tick值
    public fun min_tick(): i64::I64 {
        i64::neg_from(TICK_BOUND)
    }

    // 返回tick边界值
    // 返回值：tick边界值
    public fun tick_bound(): u64 {
        TICK_BOUND
    }

    // 根据tick值获取sqrt价格
    // 参数：tick - tick索引
    // 返回值：对应的sqrt价格
    public fun get_sqrt_price_at_tick(tick: i64::I64): u128 {
        assert!(
            i64::gte(tick, min_tick()) && i64::lte(tick, max_tick()),
            EINVALID_TICK
        );
        if (i64::is_neg(tick)) {
            get_sqrt_price_at_negative_tick(tick)
        } else {
            get_sqrt_price_at_positive_tick(tick)
        }
    }

    // 根据tick值获取fifrt价格
    // 参数：tick - tick索引
    // 返回值：对应的sqrt价格
    public fun get_fifrt_price_at_tick(tick: i64::I64): u128 {

        assert!(i64::gte(tick, min_tick()), EINVALID_TICK);
        let max_tick = max_tick();
        assert!(i64::lte(tick, max_tick), EINVALID_TICK);
        // fifth root of price of tick convet to sqrt price of tick at (tick * 2 / 5)
        let tick = i64::div(i64::mul(tick, i64::from(2)), i64::from(config::curve_degree()));
        if (i64::is_neg(tick)) {
            get_sqrt_price_at_negative_tick(tick)
        } else {
            get_sqrt_price_at_positive_tick(tick)
        }
    }


    // 验证tick索引是否有效
    // 参数：index - tick索引，tick_spacing - tick间距
    // 返回值：是否有效
    public fun is_valid_index(index: I64, tick_spacing: u64): bool {
        let in_range = i64::gte(index, min_tick()) && i64::lte(index, max_tick());
        in_range && (i64::mod(index, i64::from(tick_spacing)) == i64::from(0))
    }

    // 根据fifrt价格获取tick值
    // 参数：fifrt_price - sqrt价格
    // 返回值：对应的tick索引
    public fun get_tick_at_fifrt_price(fifrt_price: u128): i64::I64 {
        assert!(
            fifrt_price >= MIN_SQRT_PRICE_X64 && fifrt_price <= MAX_SQRT_PRICE_X64,
            EINVALID_SQRT_PRICE
        );
        let r = fifrt_price;
        let msb = 0;

        // 计算最高有效位（MSB）
        let f: u8 = as_u8(r >= 0x10000000000000000) << 6; // 如果r >= 2^64，f = 64 否则 0
        msb = msb | f;
        r = r >> f;
        f = as_u8(r >= 0x100000000) << 5; // 2^32
        msb = msb | f;
        r = r >> f;
        f = as_u8(r >= 0x10000) << 4; // 2^16
        msb = msb | f;
        r = r >> f;
        f = as_u8(r >= 0x100) << 3; // 2^8
        msb = msb | f;
        r = r >> f;
        f = as_u8(r >= 0x10) << 2; // 2^4
        msb = msb | f;
        r = r >> f;
        f = as_u8(r >= 0x4) << 1; // 2^2
        msb = msb | f;
        r = r >> f;
        f = as_u8(r >= 0x2) << 0; // 2^0
        msb = msb | f;

        // 计算log2(x) * 2^32
        let log_2_x32 = i128::shl(i128::sub(i128::from((msb as u128)), i128::from(64)), 32);

        // 标准化r到[2^63, 2^64)范围
        r =
            if (msb >= 64) {
                fifrt_price >> (msb - 63)
            } else {
                fifrt_price << (63 - msb)
            };

        // 牛顿迭代法计算对数
        let shift = 31;
        while (shift >= 18) {
            r = ((r * r) >> 63);
            f = ((r >> 64) as u8);
            log_2_x32 =
                i128::or(
                    log_2_x32,
                    i128::shl(i128::from((f as u128)), shift)
                );
            r = r >> f;
            shift = shift - 1;
        };

        //         let log_fifrt_10001 = i128::mul(log_2_x32, i128::from(59543866431366u128));
        // 计算log(fifrt(1.0001)) * 2^64
        let log_fifrt_10001 = i128::mul(log_2_x32, i128::from(148859665781220u128));

        // 计算tick的上下界
        let tick_low =
            i128::as_i64(
                i128::shr(i128::sub(log_fifrt_10001, i128::from(184467440737095516u128)), 64)
            );
        let tick_high =
            i128::as_i64(
                i128::shr(i128::add(log_fifrt_10001, i128::from(15793534762490258745u128)), 64)
            );

        // 返回正确的tick值
        if (i64::eq(tick_low, tick_high)) {
            return tick_low
        } else if (get_fifrt_price_at_tick(tick_high) <= fifrt_price) {
            return tick_high
        } else {
            return tick_low
        }
    }

    // 布尔值转换为u8
    // 参数：b - 布尔值
    // 返回值：u8值（true=1, false=0）
    fun as_u8(b: bool): u8 {
        if (b) { 1 }
        else { 0 }
    }

    // 计算负tick对应的sqrt价格
    // 参数：tick - 负tick值
    // 返回值：对应的sqrt价格
    fun get_sqrt_price_at_negative_tick(tick: i64::I64): u128 {
        let abs_tick = i64::as_u64(i64::abs(tick));
        let ratio =
            if (abs_tick & 0x1 != 0) {
                18445821805675392311u128
            } else {
                18446744073709551616u128
            };
        // 通过位运算逐步计算价格比率
        if (abs_tick & 0x2 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 18444899583751176498u128, 64u8)
        };
        if (abs_tick & 0x4 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 18443055278223354162u128, 64u8);
        };
        if (abs_tick & 0x8 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 18439367220385604838u128, 64u8);
        };
        if (abs_tick & 0x10 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 18431993317065449817u128, 64u8);
        };
        if (abs_tick & 0x20 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 18417254355718160513u128, 64u8);
        };
        if (abs_tick & 0x40 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 18387811781193591352u128, 64u8);
        };
        if (abs_tick & 0x80 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 18329067761203520168u128, 64u8);
        };
        if (abs_tick & 0x100 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 18212142134806087854u128, 64u8);
        };
        if (abs_tick & 0x200 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 17980523815641551639u128, 64u8);
        };
        if (abs_tick & 0x400 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 17526086738831147013u128, 64u8);
        };
        if (abs_tick & 0x800 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 16651378430235024244u128, 64u8);
        };
        if (abs_tick & 0x1000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 15030750278693429944u128, 64u8);
        };
        if (abs_tick & 0x2000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 12247334978882834399u128, 64u8);
        };
        if (abs_tick & 0x4000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 8131365268884726200u128, 64u8);
        };
        if (abs_tick & 0x8000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 3584323654723342297u128, 64u8);
        };
        if (abs_tick & 0x10000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 696457651847595233u128, 64u8);
        };
        if (abs_tick & 0x20000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 26294789957452057u128, 64u8);
        };
        if (abs_tick & 0x40000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 37481735321082u128, 64u8);
        };

        ratio
    }

    // 计算正tick对应的sqrt价格
    // 参数：tick - 正tick值
    // 返回值：对应的sqrt价格
    fun get_sqrt_price_at_positive_tick(tick: i64::I64): u128 {
        let abs_tick = i64::as_u64(i64::abs(tick));
        let ratio =
            if (abs_tick & 0x1 != 0) {
                79232123823359799118286999567u128
            } else {
                79228162514264337593543950336u128
            };

        // 通过位运算逐步计算价格比率（正tick）
        if (abs_tick & 0x2 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 79236085330515764027303304731u128, 96u8
            )
        };
        if (abs_tick & 0x4 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 79244008939048815603706035061u128, 96u8
            )
        };
        if (abs_tick & 0x8 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 79259858533276714757314932305u128, 96u8
            )
        };
        if (abs_tick & 0x10 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 79291567232598584799939703904u128, 96u8
            )
        };
        if (abs_tick & 0x20 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 79355022692464371645785046466u128, 96u8
            )
        };
        if (abs_tick & 0x40 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 79482085999252804386437311141u128, 96u8
            )
        };
        if (abs_tick & 0x80 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 79736823300114093921829183326u128, 96u8
            )
        };
        if (abs_tick & 0x100 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 80248749790819932309965073892u128, 96u8
            )
        };
        if (abs_tick & 0x200 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 81282483887344747381513967011u128, 96u8
            )
        };
        if (abs_tick & 0x400 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 83390072131320151908154831281u128, 96u8
            )
        };
        if (abs_tick & 0x800 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 87770609709833776024991924138u128, 96u8
            )
        };
        if (abs_tick & 0x1000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 97234110755111693312479820773u128, 96u8
            )
        };
        if (abs_tick & 0x2000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 119332217159966728226237229890u128, 96u8
            )
        };
        if (abs_tick & 0x4000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 179736315981702064433883588727u128, 96u8
            )
        };
        if (abs_tick & 0x8000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 407748233172238350107850275304u128, 96u8
            )
        };
        if (abs_tick & 0x10000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 2098478828474011932436660412517u128, 96u8
            )
        };
        if (abs_tick & 0x20000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 55581415166113811149459800483533u128, 96u8
            )
        };
        if (abs_tick & 0x40000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 38992368544603139932233054999993551u128, 96u8
            )
        };

        ratio >> 32
    }

    // 测试函数 - 测试根据tick获取sqrt价格
    #[test]
    fun test_get_fifrt_price_at_tick() {
        // 最小tick
        assert!(get_fifrt_price_at_tick(i64::neg_from(TICK_BOUND)) == 4295048016u128, 2);
        // 最大tick
        assert!(
            get_fifrt_price_at_tick(i64::from(TICK_BOUND))
                == 79226673515401279992447579055u128,
            1
        );
        assert!(get_fifrt_price_at_tick(i64::neg_from(435444u64)) == 6469134034u128, 3);
        assert!(
            get_fifrt_price_at_tick(i64::from(408332u64))
                == 13561044167458152057771544136u128,
            4
        );
    }

    // 测试函数 - 测试tick和sqrt价格的相互转换
    #[test]
    fun test_tick_swap_fifrt_price() {
        let t = i64::neg_from(1109090);
        while (i64::lte(t, i64::from(1109090))) {
            let fifrt_price = get_fifrt_price_at_tick(t);
            let tick = get_tick_at_fifrt_price(fifrt_price);
            if (i64::is_neg(t)) {
                print(&string_utils::format2(&b"-{} -{}", i64::abs(t), i64::abs(tick)));
            } else {
                print(&string_utils::format2(&b"{} {}", i64::abs(t), i64::abs(tick)));
            };
            //assert!(i64::eq(t, tick) == true, 0);
            t = i64::add(t, i64::from(10000));
        }
    }

    // 测试函数 - 测试根据sqrt价格获取tick
    #[test]
    fun test_get_tick_at_fifrt_price_1() {
        assert!(
            i64::eq(get_tick_at_fifrt_price(6469134034u128), i64::neg_from(435444))
                == true,
            0
        );
        assert!(
            i64::eq(
                get_tick_at_fifrt_price(13561044167458152057771544136u128),
                i64::from(408332u64)
            ) == true,
            0
        );
    }

    // 测试函数 - 测试无效的上界tick（期望失败）
    #[test]
    #[expected_failure]
    fun test_get_fifrt_price_at_invalid_upper_tick() {
        get_fifrt_price_at_tick(i64::add(max_tick(), i64::from(1)));
    }

    // 测试函数 - 测试无效的下界tick（期望失败）
    #[test]
    #[expected_failure]
    fun test_get_fifrt_price_at_invalid_lower_tick() {
        get_fifrt_price_at_tick(i64::sub(min_tick(), i64::from(1)));
    }

    // 测试函数 - 测试无效的下界sqrt价格（期望失败）
    #[test]
    #[expected_failure]
    fun test_get_tick_at_invalid_lower_fifrt_price() {
        get_tick_at_fifrt_price(MAX_SQRT_PRICE_X64 + 1);
    }

    // 测试函数 - 测试无效的上界sqrt价格（期望失败）
    #[test]
    #[expected_failure]
    fun test_get_tick_at_invalid_upper_fifrt_price() {
        get_tick_at_fifrt_price(MIN_SQRT_PRICE_X64 - 1);
    }
}
