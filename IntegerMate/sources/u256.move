/// 256位无符号整数模块
/// 提供了完整的256位算术运算，用于高精度计算
/// 在DEX中用于处理需要高精度的大数计算，如复杂的价格和流动性计算
module integer_mate::u256 {
    use std::error;
    use integer_mate::math_u64;
    use integer_mate::math_u128;

    /// 溢出错误代码
    const OVERFLOW: u64 = 0;
    /// 除零错误代码
    const DIV_BY_ZERO: u64 = 1;

    /// 比较结果常量：小于
    const LT: u8 = 0;
    /// 比较结果常量：等于
    const EQ: u8 = 1;
    /// 比较结果常量：大于
    const GT: u8 = 2;

    /// 高64位掩码，用于提取128位数字的高64位
    const HI_64_MASK: u128 = 0xffffffffffffffff0000000000000000;
    /// 低64位掩码，用于提取128位数字的低64位
    const LO_64_MASK: u128 = 0x0000000000000000ffffffffffffffff;

    /// 128位最大值
    const MAX_U128: u128 = 0xffffffffffffffffffffffffffffffff;
    /// 64位最大值
    const MAX_U64: u64 = 0xffffffffffffffff;

    /// U256中的64位字数量（64 * 4 = 256）
    const WORDS: u8 = 4;

    /// 256位无符号整数结构体
    /// 使用4个64位无符号整数来表示一个256位数字（小端序）
    struct U256 has copy, drop, store {
        n0: u64, // 最低64位
        n1: u64, // 次低64位
        n2: u64, // 次高64位
        n3: u64 // 最高64位
    }

    /// 创建零值U256
    /// 返回：值为0的U256
    public fun zero(): U256 {
        U256 { n0: 0, n1: 0, n2: 0, n3: 0 }
    }

    /// 从u128创建U256
    /// 参数：n - 128位无符号整数
    /// 返回：对应的U256值
    public fun from(n: u128): U256 {
        U256 {
            n0: ((n & LO_64_MASK) as u64),
            n1: ((n >> 64) as u64),
            n2: 0u64,
            n3: 0u64
        }
    }

    /// 使用4个u64创建U256
    /// 参数：n0 - 最低64位，n1 - 次低64位，n2 - 次高64位，n3 - 最高64位
    /// 返回：构造的U256值
    public fun new(n0: u64, n1: u64, n2: u64, n3: u64): U256 {
        U256 { n0, n1, n2, n3 }
    }

    /// 加法：执行两个U256数字的加法运算
    /// 参数：a - 第一个操作数，b - 第二个操作数
    /// 返回：加法结果
    public fun add(a: U256, b: U256): U256 {
        let (sum0, carry0) = math_u64::carry_add(a.n0, b.n0, 0);
        let (sum1, carry1) = math_u64::carry_add(a.n1, b.n1, carry0);
        let (sum2, carry2) = math_u64::carry_add(a.n2, b.n2, carry1);
        let (sum3, carry3) = math_u64::carry_add(a.n3, b.n3, carry2);
        assert!(carry3 == 0, error::invalid_argument(OVERFLOW));
        U256 { n0: sum0, n1: sum1, n2: sum2, n3: sum3 }
    }

    /// 减法：执行两个U256数字的减法运算
    /// 参数：a - 被减数，b - 减数
    /// 返回：减法结果
    public fun sub(a: U256, b: U256): U256 {
        let (r0, overflow_s0) = math_u64::overflowing_sub(a.n0, b.n0);
        let carry0 = if (overflow_s0) { 1 }
        else { 0 };
        let (t1, overflow_t1) = math_u64::overflowing_sub(a.n1, b.n1);
        let (r1, overflow_s1) = math_u64::overflowing_sub(t1, carry0);
        let carry1 = if (overflow_t1 || overflow_s1) { 1 }
        else { 0 };
        let (t2, overflow_t2) = math_u64::overflowing_sub(a.n2, b.n2);
        let (r2, overflow_s2) = math_u64::overflowing_sub(t2, carry1);
        let carry2 = if (overflow_t2 || overflow_s2) { 1 }
        else { 0 };
        let (t3, overflow_t3) = math_u64::overflowing_sub(a.n3, b.n3);
        let (r3, overflow_s3) = math_u64::overflowing_sub(t3, carry2);
        let carry3 = if (overflow_t3 || overflow_s3) { 1 }
        else { 0 };
        assert!(carry3 == 0, error::invalid_argument(OVERFLOW));
        U256 { n0: r0, n1: r1, n2: r2, n3: r3 }
    }

    /// 乘法：执行两个U256数字的乘法运算（不触发溢出）
    /// 参数：a - 第一个操作数，b - 第二个操作数
    /// 返回：乘法结果
    public fun mul(a: U256, b: U256): U256 {
        let result = zero();
        let m = num_words(a);
        let n = num_words(b);
        let j = 0u8;
        while (j < n) {
            let k = 0u128;
            let i = 0u8;
            while (i < m) {
                let x = (get(&a, i) as u128);
                let y = (get(&b, j) as u128);
                if ((i + j) < 4) {
                    let z = (get(&result, i + j) as u128);
                    let t =
                        math_u128::wrapping_add(
                            math_u128::wrapping_add(math_u128::wrapping_mul(x, y), z),
                            k
                        );
                    set(&mut result, (i + j), math_u128::lo(t));
                    k = math_u128::hi_u128(t);
                };
                i = i + 1;
            };
            if ((j + m) < 4) {
                set(&mut result, (j + m), (k as u64));
            };
            j = j + 1;
        };
        result
    }

    /// 除法和取模：执行除法运算并返回商和余数
    /// 参数：a - 被除数，b - 除数
    /// 返回：(商, 余数)
    public fun div_mod(a: U256, b: U256): (U256, U256) {
        let ret = zero();
        let remainer = a;

        let a_bits = bits(&a);
        let b_bits = bits(&b);

        assert!(b_bits != 0, DIV_BY_ZERO); // 除零检查
        if (a_bits < b_bits) {
            // 如果被除数小于除数，直接返回
            return (ret, remainer)
        };

        let shift = a_bits - b_bits;
        b = shl(b, (shift as u8));

        loop {
            if (gte(a, b)) {
                let index = shift / 64;
                let m = get(&ret, (index as u8));
                let c = m | 1 << ((shift % 64) as u8);
                set(&mut ret, (index as u8), c);

                a = sub(a, b);
            };

            b = shr(b, 1);
            if (shift == 0) {
                remainer = a;
                break
            };

            shift = shift - 1;
        };

        (ret, remainer)
    }

    /// 除法：执行除法运算
    /// 参数：a - 被除数，b - 除数
    /// 返回：商
    public fun div(a: U256, b: U256): U256 {
        let (q, _) = div_mod(a, b);
        q
    }

    /// 转换为u128（检查溢出）
    /// 参数：n - U256数字
    /// 返回：对应的u128值
    public fun as_u128(n: U256): u128 {
        assert!(
            n.n3 == 0 && n.n2 == 0,
            error::invalid_argument(OVERFLOW)
        );
        math_u128::from_lo_hi(n.n0, n.n1)
    }

    /// 转换为u64（检查溢出）
    /// 参数：n - U256数字
    /// 返回：对应的u64值
    public fun as_u64(n: U256): u64 {
        assert!(
            n.n3 == 0 && n.n2 == 0 && n.n1 == 0,
            error::invalid_argument(OVERFLOW)
        );
        n.n0
    }

    /// 安全转换为u128
    /// 参数：n - U256数字
    /// 返回：(转换结果, 是否溢出)
    public fun checked_as_u128(n: U256): (u128, bool) {
        if ((n.n3 != 0) || (n.n2 != 0)) {
            return (0, true)
        };
        (math_u128::from_lo_hi(n.n0, n.n1), false)
    }

    /// 安全转换为u64
    /// 参数：n - U256数字
    /// 返回：(转换结果, 是否溢出)
    public fun checked_as_u64(n: U256): (u64, bool) {
        if (n.n3 != 0 || n.n2 != 0 || n.n1 != 0) {
            return (0, true)
        };
        (n.n0, false)
    }

    /// 左移64位：将数字向左移动64位（不触发溢出）
    /// 参数：n - 输入的U256数字
    /// 返回：左移64位后的结果
    public fun shlw(n: U256): U256 {
        U256 { n0: 0, n1: n.n0, n2: n.n1, n3: n.n2 }
    }

    /// 右移64位：将数字向右移动64位（不触发溢出）
    /// 参数：n - 输入的U256数字
    /// 返回：右移64位后的结果
    public fun shrw(n: U256): U256 {
        U256 { n0: n.n1, n1: n.n2, n2: n.n3, n3: 0 }
    }

    public fun checked_shlw(n: U256): (U256, bool) {
        if (n.n3 > 0) {
            return (zero(), true)
        };
        (shlw(n), false)
    }

    public fun shl(n: U256, shift: u8): U256 {
        let result = n;
        let num = shift;

        while (num >= 64) {
            result = shlw(result);
            num = num - 64;
        };
        if (num == 0) {
            return result
        };

        result.n3 = result.n3 << num | (result.n2 >> (64 - num));
        result.n2 = result.n2 << num | (result.n1 >> (64 - num));
        result.n1 = result.n1 << num | (result.n0 >> (64 - num));
        result.n0 = result.n0 << num;

        result
    }

    public fun shr(n: U256, shift: u8): U256 {
        let result = n;
        let num = shift;

        while (num >= 64) {
            result = shrw(result);
            num = num - 64;
        };
        if (num == 0) {
            return result
        };

        result.n0 = result.n0 >> num | (result.n1 << (64 - num));
        result.n1 = result.n1 >> num | (result.n2 << (64 - num));
        result.n2 = result.n2 >> num | (result.n3 << (64 - num));
        result.n3 = result.n3 >> num;

        result
    }

    public fun cmp(a: U256, b: U256): u8 {
        let i = 4;
        while (i > 0) {
            i = i - 1;
            let ai = get(&a, i);
            let bi = get(&b, i);
            if (ai != bi) {
                if (ai < bi) {
                    return LT
                } else {
                    return GT
                }
            }
        };

        EQ
    }

    public fun eq(num1: U256, num2: U256): bool {
        cmp(num1, num2) == EQ
    }

    public fun gt(num1: U256, num2: U256): bool {
        cmp(num1, num2) == GT
    }

    public fun gte(num1: U256, num2: U256): bool {
        cmp(num1, num2) >= EQ
    }

    public fun lt(num1: U256, num2: U256): bool {
        cmp(num1, num2) == LT
    }

    public fun lte(num1: U256, num2: U256): bool {
        cmp(num1, num2) <= EQ
    }

    // TODO: Add test
    public fun checked_div_round(num: U256, denom: U256, round_up: bool): U256 {
        let (q, r) = div_mod(num, denom);
        if (round_up && gt(r, zero())) {
            return add(q, from(1))
        };
        q
    }

    public fun lo_u128(num: U256): u128 {
        (((num.n1 as u128) << 64) + (num.n0 as u128))
    }

    public fun hi_u128(num: U256): u128 {
        (((num.n3 as u128) << 64) + (num.n2 as u128))
    }

    public fun get(a: &U256, i: u8): u64 {
        if (i == 0) { a.n0 }
        else if (i == 1) { a.n1 }
        else if (i == 2) { a.n2 }
        else if (i == 3) { a.n3 }
        else {
            abort OVERFLOW
        }
    }

    fun num_words(a: U256): u8 {
        let n = 0;
        if (a.n0 > 0) {
            n = n + 1;
        };
        if (a.n1 > 0) {
            n = n + 1;
        };
        if (a.n2 > 0) {
            n = n + 1;
        };
        if (a.n3 > 0) {
            n = n + 1
        };
        n
    }

    fun set(a: &mut U256, i: u8, v: u64) {
        if (i == 0) {
            a.n0 = v;
        } else if (i == 1) {
            a.n1 = v;
        } else if (i == 2) {
            a.n2 = v;
        } else if (i == 3) {
            a.n3 = v;
        } else {
            abort OVERFLOW
        }
    }

    fun bits(a: &U256): u64 {
        let i = 1;
        while (i < WORDS) {
            let a1 = get(a, WORDS - i);
            if (a1 > 0) {
                return (((0x40 as u64) * ((WORDS - i + 1) as u64))
                    - (leading_zeros_u64(a1) as u64))
            };

            i = i + 1;
        };

        let a1 = get(a, 0);
        0x40 - (leading_zeros_u64(a1) as u64)
    }

    fun leading_zeros_u64(a: u64): u8 {
        if (a == 0) {
            return 64
        };

        let a1 = a & 0xFFFFFFFF;
        let a2 = a >> 32;

        if (a2 == 0) {
            let bit = 32;

            while (bit >= 1) {
                let b = (a1 >> (bit - 1)) & 1;
                if (b != 0) { break };

                bit = bit - 1;
            };

            (32 - bit) + 32
        } else {
            let bit = 64;
            while (bit >= 1) {
                let b = (a >> (bit - 1)) & 1;
                if (b != 0) { break };
                bit = bit - 1;
            };

            64 - bit
        }
    }

    #[test]
    fun test_from() {
        let v = from(0x80000000000000000000000000000010);
        assert!(v.n0 == 0x10, 0);
        assert!(v.n1 == 1 << 63, 0);
    }

    #[test]
    fun test_add() {
        let s = add(new(10, 10, 10, 10), new(10, 10, 10, 10));
        assert!(s.n0 == 20 && s.n1 == 20 && s.n2 == 20 && s.n3 == 20, 0);

        let s =
            add(
                from(0xffffffffffffffffffffffffffffffff),
                from(0xffffffffffffffffffffffffffffffff)
            );
        assert!(
            s.n0 == 18446744073709551614
                && s.n1 == 18446744073709551615
                && s.n2 == 1
                && s.n3 == 0,
            0
        );

        let max = MAX_U64;
        let s = add(new(max, max, max, 10), new(max, max, max, 10));
        assert!(
            s.n0 == 18446744073709551614
                && s.n1 == 18446744073709551615
                && s.n2 == 18446744073709551615
                && s.n3 == 21,
            0
        );
    }

    #[test]
    #[expected_failure]
    fun test_add_overflow() {
        // TODO: Add more test
        add(new(10, 100, 1000, MAX_U64), new(11, 101, 1001, 1));
    }

    #[test]
    fun test_sub() {
        // TODO: Add more test
        let s = sub(
            new(10, 100, 1000, 10000),
            new(11, 101, 1001, 1000)
        );
        assert!(
            s.n0 == 18446744073709551615
                && s.n1 == 18446744073709551614
                && s.n2 == 18446744073709551614
                && s.n3 == 8999,
            0
        );
    }

    #[test]
    #[expected_failure]
    fun test_sub_overflow() {
        // TODO: Add more test
        sub(
            new(10, 100, 1000, 10000),
            new(11, 101, 1001, 10000)
        );
    }

    #[test]
    fun test_mul() {
        let r = mul(from(10), from(10));
        assert!(r.n0 == 100 && r.n1 == 0 && r.n2 == 0 && r.n3 == 0, 0);

        let r = mul(from(0), from(10));
        assert!(r.n0 == 0 && r.n1 == 0 && r.n2 == 0 && r.n3 == 0, 0);

        let r = mul(from(10), from(0));
        assert!(r.n0 == 0 && r.n1 == 0 && r.n2 == 0 && r.n3 == 0, 0);

        let r = mul(from(999999), from(999999));
        assert!(
            r.n0 == 999998000001 && r.n1 == 0 && r.n2 == 0 && r.n3 == 0,
            0
        );

        let r = mul(from(MAX_U128), from(2));
        assert!(
            r.n0 == 18446744073709551614
                && r.n1 == 18446744073709551615
                && r.n2 == 1
                && r.n3 == 0,
            0
        );

        let r = mul(from(2), from(MAX_U128));
        assert!(
            r.n0 == 18446744073709551614
                && r.n1 == 18446744073709551615
                && r.n2 == 1
                && r.n3 == 0,
            0
        );

        let r = mul(from(MAX_U128), from((MAX_U64 as u128)));
        assert!(
            r.n0 == 1
                && r.n1 == 18446744073709551615
                && r.n2 == 18446744073709551614
                && r.n3 == 0,
            0
        );

        let r = mul(from(MAX_U128), from(MAX_U128));
        assert!(
            eq(
                r,
                new(
                    1,
                    0,
                    18446744073709551614,
                    18446744073709551615
                )
            ) == true,
            0
        );

        mul(new(10, 10, 10, 10), new(10, 10, 10, 10));

        // TODO: Add more test
    }

    #[test]
    fun test_div() {
        // TODO: Add more test
        let a = from(100);
        let b = from(5);
        let d = div(a, b);
        assert!(as_u128(d) == 20, 0);

        let a = from((MAX_U64 as u128));
        let b = from(MAX_U128);
        let d = div(a, b);
        assert!(as_u128(d) == 0, 1);

        let a = from((MAX_U64 as u128));
        let b = from(MAX_U128);
        let d = div(a, b);
        assert!(as_u128(d) == 0, 2);

        let a = from(MAX_U128);
        let b = from((MAX_U64 as u128));
        let d = div(a, b);
        assert!(as_u128(d) == 18446744073709551617, 2);

        let m =
            new(
                10655214313433269453,
                15734150612341066489,
                14649800231932480840,
                7840575814708351719
            );
        let n =
            new(
                14649800231932480840,
                7840575814708351719,
                10655214313433269453,
                15734150612341066489
            );
        let (q, r) = div_mod(m, n);
        assert!(eq(q, zero()) == true, 0);
        assert!(
            eq(
                r,
                new(
                    10655214313433269453,
                    15734150612341066489,
                    14649800231932480840,
                    7840575814708351719
                )
            ) == true,
            0
        );

        let m =
            new(
                12636451795089125100,
                10304548827917701964,
                2223071594322190165,
                18320302927055064890
            );
        let n =
            new(
                2223071594322190165,
                14427030292705506480,
                12636451795089125100,
                427701964
            );
        let (q, r) = div_mod(m, n);
        assert!(eq(q, new(42834273488, 0, 0, 0)) == true, 0);
        assert!(
            eq(
                r,
                new(
                    15466148154527319516,
                    8118191964138314409,
                    1682799980586770877,
                    381853750
                )
            ) == true,
            0
        );

    }

    #[test]
    fun test_shl() {
        assert!(eq(shl(from(10), 2), from(10 << 2)) == true, 0);
        assert!(eq(shl(from(10), 8), from(10 << 8)) == true, 0);
        assert!(eq(shl(from(10), 16), from(10 << 16)) == true, 0);
        assert!(eq(shl(from(10), 32), from(10 << 32)) == true, 0);
        assert!(eq(shl(from(10), 64), from(10 << 64)) == true, 0);
        assert!(eq(shl(from(10), 120), from(10 << 120)) == true, 0);
        assert!(eq(shl(from(10), 128), new(0, 0, 10, 0)) == true, 0);
        assert!(
            eq(
                shl(from(10), 190),
                new(0, 0, 9223372036854775808, 2)
            ) == true,
            0
        );
        assert!(eq(shl(from(10), 192), new(0, 0, 0, 10)) == true, 0);
        assert!(
            eq(shl(from(10), 196), new(0, 0, 0, 160)) == true,
            0
        );
        assert!(
            eq(
                shl(from(10), 250),
                new(0, 0, 0, 2882303761517117440)
            ) == true,
            0
        );
        assert!(
            eq(
                shl(from(1), 255),
                new(0, 0, 0, 9223372036854775808)
            ) == true,
            0
        );
        assert!(eq(shl(from(2), 255), new(0, 0, 0, 0)) == true, 0);
    }

    #[test]
    fun test_shr() {
        assert!(eq(shr(from(99), 0), new(99, 0, 0, 0)) == true, 0);
        assert!(eq(shr(from(99), 1), new(49, 0, 0, 0)) == true, 0);
        assert!(eq(shr(from(99), 2), new(24, 0, 0, 0)) == true, 0);
        assert!(eq(shr(from(99), 8), new(0, 0, 0, 0)) == true, 0);

        assert!(
            eq(
                shr(from(MAX_U128), 16),
                new(18446744073709551615, 281474976710655, 0, 0)
            ) == true,
            0
        );
        assert!(
            eq(
                shr(from(MAX_U128), 63),
                new(18446744073709551615, 1, 0, 0)
            ) == true,
            0
        );
        assert!(
            eq(
                shr(from(MAX_U128), 64),
                new(18446744073709551615, 0, 0, 0)
            ) == true,
            0
        );
        assert!(
            eq(
                shr(from(MAX_U128), 65),
                new(9223372036854775807, 0, 0, 0)
            ) == true,
            0
        );
        assert!(
            eq(shr(from(MAX_U128), 127), new(1, 0, 0, 0)) == true,
            0
        );

        assert!(
            eq(
                shr(new(MAX_U64, MAX_U64, MAX_U64, MAX_U64), 191),
                new(18446744073709551615, 1, 0, 0)
            ) == true,
            0
        );
        assert!(
            eq(
                shr(new(MAX_U64, MAX_U64, MAX_U64, MAX_U64), 192),
                new(18446744073709551615, 0, 0, 0)
            ) == true,
            0
        );
        assert!(
            eq(
                shr(new(MAX_U64, MAX_U64, MAX_U64, MAX_U64), 193),
                new(9223372036854775807, 0, 0, 0)
            ) == true,
            0
        );
        assert!(
            eq(
                shr(new(MAX_U64, MAX_U64, MAX_U64, MAX_U64), 255),
                new(1, 0, 0, 0)
            ) == true,
            0
        );
    }

    #[test]
    fun test_compare() {
        assert!(cmp(from(99), from(99)) == EQ, 0);
        assert!(
            cmp(new(100, 100, 100, 100), new(100, 100, 100, 101)) == LT,
            0
        );
        assert!(
            cmp(new(100, 100, 100, 101), new(100, 100, 100, 100)) == GT,
            0
        );
        assert!(
            cmp(new(100, 100, 100, 100), new(100, 100, 100, 100)) == EQ,
            0
        );

        assert!(
            eq(new(100, 100, 100, 100), new(100, 100, 100, 100)) == true,
            0
        );
        assert!(
            lte(new(100, 100, 100, 100), new(100, 100, 100, 100)) == true,
            0
        );
        assert!(
            lte(new(100, 100, 100, 100), new(100, 100, 100, 101)) == true,
            0
        );
        assert!(
            lt(new(100, 100, 100, 100), new(100, 100, 100, 101)) == true,
            0
        );

        assert!(
            lte(
                new(100000, 100, 100, 100),
                new(100, 100, 100, 101)
            ) == true,
            0
        );
        assert!(
            lt(
                new(100000, 100, 100000, 100),
                new(100, 100, 100, 101)
            ) == true,
            0
        );

        assert!(
            gte(new(100, 100, 100, 101), new(100, 100, 100, 101)) == true,
            0
        );
        assert!(
            gte(new(100, 100, 100, 101), new(100, 100, 100, 100)) == true,
            0
        );
        assert!(
            gt(new(100, 100, 100, 101), new(100, 100, 100, 100)) == true,
            0
        );

        assert!(
            gte(new(100, 100, 100, 101), new(100, 100, 99999, 100)) == true,
            0
        );
        assert!(
            gt(new(100, 100, 100, 101), new(100, 100, 99999, 100)) == true,
            0
        );
    }

    #[test]
    fun test_check_div_round() {
        assert!(
            eq(
                checked_div_round(from(23), from(10), false),
                from(2)
            ) == true,
            0
        );
        assert!(
            eq(
                checked_div_round(from(23), from(10), true),
                from(3)
            ) == true,
            0
        );
        assert!(
            eq(
                checked_div_round(from(20), from(10), true),
                from(2)
            ) == true,
            0
        );
        assert!(
            eq(
                checked_div_round(from(2), from(10), true),
                from(1)
            ) == true,
            0
        );

        assert!(
            eq(
                checked_div_round(from(MAX_U128), from(10), true),
                from((MAX_U128 / 10) + 1)
            ) == true,
            0
        );
        assert!(
            eq(
                checked_div_round(from(MAX_U128), from(10), false),
                from((MAX_U128 / 10))
            ) == true,
            0
        );

        //assert!(eq(checked_div_round(from(MAX_U128), from((MAX_U64 as u128)), true), from((MAX_U128 / 10) + 1)) == true, 0);
        //assert!(eq(checked_div_round(from(MAX_U128), from((MAX_U64 as u128)), false), from((MAX_U128 / 10))) == true, 0);
    }
}
