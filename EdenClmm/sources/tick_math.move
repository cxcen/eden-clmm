/// Tick价格数学计算模块
/// 该模块提供了tick索引和sqrt价格之间的转换功能
/// 类似于Uniswap V3的tick数学运算，用于集中流动性管理
module eden_clmm::tick_math {
    use aptos_std::debug::print;
    use eden_clmm::config;
    use integer_mate::full_math_u128;
    use integer_mate::i64::{Self, I64};
    use integer_mate::i128;


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
        print(&tick);

        assert!(i64::gte(tick, min_tick()), EINVALID_TICK);
        let max_tick = max_tick();
        print(&max_tick);
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
                0xfffcb933bd6fad37aa2d162d1u128 // 18445821805675392311
            } else {
                0x10000000000000000u128 // 18446744073709551616
            };
        // 通过位运算逐步计算价格比率
        if (abs_tick & 0x2 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xfff97272373d413259a469905u128, 64u8); // 18444899583751176498
        };
        if (abs_tick & 0x4 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xfff2e50f5f656932ef12357cfu128, 64u8); // 18443055278223354162
        };
        if (abs_tick & 0x8 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xffe5caca7e10e4e61c3624eaau128, 64u8); // 18439367220385604838
        };
        if (abs_tick & 0x10 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xffcb9843d60f6159c9db58835u128, 64u8); // 18431993317065449817
        };
        if (abs_tick & 0x20 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xff973b41fa98c081472e6896du128, 64u8); // 18417254355718160513
        };
        if (abs_tick & 0x40 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xff2ea16466c96a3843ec78b33u128, 64u8); // 18387811781193591352
        };
        if (abs_tick & 0x80 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xfe5dee046a99a2a811c461f196u128, 64u8); // 18329067761203520168
        };
        if (abs_tick & 0x100 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xfcbe86c7900a88aedcffc83b479u128, 64u8); // 18212142134806087854
        };
        if (abs_tick & 0x200 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xf987a7253ac413176f2b074cfu128, 64u8); // 17980523815641551639
        };
        if (abs_tick & 0x400 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xf3392b0822b70005940c7a398u128, 64u8); // 17526086738831147013
        };
        if (abs_tick & 0x800 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xe7159475a2c29b7443b29c7fa6u128, 64u8); // 16651378430235024244
        };
        if (abs_tick & 0x1000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xd097f3bdfd2022b8845ad8f792u128, 64u8); // 15030750278693429944
        };
        if (abs_tick & 0x2000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0xa9f746462d870fdf8a65dc1f90u128, 64u8); // 12247334978882834399
        };
        if (abs_tick & 0x4000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0x70d869a156d2a1b890bb3df62baf32u128, 64u8); // 8131365268884726200
        };
        if (abs_tick & 0x8000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0x31be135f97d08fd981231505542fcfa6u128, 64u8); // 3584323654723342297
        };
        if (abs_tick & 0x10000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0x9aa508b5b7a84e1c677de54f3e99bc9u128, 64u8); // 696457651847595233
        };
        if (abs_tick & 0x20000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0x5d6af8dedb81196699c329225ee604u128, 64u8); // 26294789957452057
        };
        if (abs_tick & 0x40000 != 0) {
            ratio = full_math_u128::mul_shr(ratio, 0x2216e584f5fa1ea926041bedfe98u128, 64u8); // 37481735321082
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
                0x0bfcbd7bb5f6c38b63b76b153u128 // 79232123823359799118286999567
            } else {
                0x1000000000000000000000000u128 // 79228162514264337593543950336
            };

        if (abs_tick & 0x2 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x0bfd4b27c5bfffd7b4f7e0d0b3u128, 96u8 // 79236085330515764027303304731
            )
        };
        if (abs_tick & 0x4 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x0bffdf58f06fd22d4fbb81bd05u128, 96u8 // 79244008939048815603706035061
            )
        };
        if (abs_tick & 0x8 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x0c0452e77038b4be8fe5106f91u128, 96u8 // 79259858533276714757314932305
            )
        };
        if (abs_tick & 0x10 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x0c0d2d1d5e0e3bc278aa7ff560u128, 96u8 // 79291567232598584799939703904
            )
        };
        if (abs_tick & 0x20 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x0c2f65d739d8b705b1c5feab52u128, 96u8 // 79355022692464371645785046466
            )
        };
        if (abs_tick & 0x40 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x0c7399e4e7556d6442a2fd9c75u128, 96u8 // 79482085999252804386437311141
            )
        };
        if (abs_tick & 0x80 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x0ce7dfd0a27edc3ed0b1d2b89eu128, 96u8 // 79736823300114093921829183326
            )
        };
        if (abs_tick & 0x100 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x0deb13496b378b3818db1e60e4u128, 96u8 // 80248749790819932309965073892
            )
        };
        if (abs_tick & 0x200 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x0e44279e6d0e67836e5db67a43u128, 96u8 // 81282483887344747381513967011
            )
        };
        if (abs_tick & 0x400 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x0f27f616b3807c0e6e5aee3431u128, 96u8 // 83390072131320151908154831281
            )
        };
        if (abs_tick & 0x800 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x133cd7cd5c8b87a3f5cbd37f1au128, 96u8 // 87770609709833776024991924138
            )
        };
        if (abs_tick & 0x1000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x152f011185b3bda863eaacdf25u128, 96u8 // 97234110755111693312479820773
            )
        };
        if (abs_tick & 0x2000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x1a13aa2b8cc21fdc94c5e6ffb2u128, 96u8 // 119332217159966728226237229890
            )
        };
        if (abs_tick & 0x4000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x27d9e6e41992f9b92b11f20437u128, 96u8 // 179736315981702064433883588727
            )
        };
        if (abs_tick & 0x8000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x5a84f6a4b9e3216f5f2a1abbd8u128, 96u8 // 407748233172238350107850275304
            )
        };
        if (abs_tick & 0x10000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x1dbbb8b08e4a361509091ba1355u128, 96u8 // 2098478828474011932436660412517
            )
        };
        if (abs_tick & 0x20000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0xc55f7995b7da3fc59f9a3ed3bcu128, 96u8 // 55581415166113811149459800483533
            )
        };
        if (abs_tick & 0x40000 != 0) {
            ratio = full_math_u128::mul_shr(
                ratio, 0x20a1c0d811d6dc3efb9ca1e17a7u128, 96u8 // 38992368544603139932233054999993551
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
        let t = i64::from(400800);
        while (i64::lte(t, i64::from(401200))) {
            print(&t);
            let fifrt_price = get_fifrt_price_at_tick(t);
            print(&fifrt_price);
            let tick = get_tick_at_fifrt_price(fifrt_price);
            assert!(i64::eq(t, tick) == true, 0);
            t = i64::add(t, i64::from(1));
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
