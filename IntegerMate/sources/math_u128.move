/// 128位无符号整数数学运算模块
/// 提供了安全的算术运算，包括溢出检查和完整乘法运算
module integer_mate::math_u128 {

    /// 128位无符号整数的最大值
    const MAX_U128: u128 = 0xffffffffffffffffffffffffffffffff;

    /// 高64位掩码，用于提取128位数字的高64位
    const HI_64_MASK: u128 = 0xffffffffffffffff0000000000000000;
    /// 低64位掩码，用于提取128位数字的低64位
    const LO_64_MASK: u128 = 0x0000000000000000ffffffffffffffff;
    /// 低128位掩码，用于从256位数字提取低128位
    const LO_128_MASK: u256 =
        0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;

    /// 除零错误代码
    const DIV_BY_ZERO: u64 = 1;

    /// 环绕加法：执行加法运算，如果溢出则环绕
    /// 参数：n1 - 第一个操作数，n2 - 第二个操作数
    /// 返回：加法结果（溢出时环绕）
    public fun wrapping_add(n1: u128, n2: u128): u128 {
        let (sum, _) = overflowing_add(n1, n2);
        sum
    }

    /// 溢出检查加法：执行加法运算并返回是否溢出
    /// 参数：n1 - 第一个操作数，n2 - 第二个操作数
    /// 返回：(结果, 是否溢出)
    public fun overflowing_add(n1: u128, n2: u128): (u128, bool) {
        let sum = (n1 as u256) + (n2 as u256);
        if (sum > (MAX_U128 as u256)) {
            (((sum & LO_128_MASK) as u128), true)
        } else {
            ((sum as u128), false)
        }
    }

    /// 环绕减法：执行减法运算，如果溢出则环绕
    /// 参数：n1 - 被减数，n2 - 减数
    /// 返回：减法结果（溢出时环绕）
    public fun wrapping_sub(n1: u128, n2: u128): u128 {
        let (result, _) = overflowing_sub(n1, n2);
        result
    }

    /// 溢出检查减法：执行减法运算并返回是否溢出
    /// 参数：n1 - 被减数，n2 - 减数
    /// 返回：(结果, 是否溢出)
    public fun overflowing_sub(n1: u128, n2: u128): (u128, bool) {
        if (n1 >= n2) {
            ((n1 - n2), false)
        } else {
            ((MAX_U128 - n2 + n1 + 1), true)
        }
    }

    /// 环绕乘法：执行乘法运算，如果溢出则环绕
    /// 参数：n1 - 第一个操作数，n2 - 第二个操作数
    /// 返回：乘法结果（溢出时环绕）
    public fun wrapping_mul(n1: u128, n2: u128): u128 {
        let (m, _) = overflowing_mul(n1, n2);
        m
    }

    /// 溢出检查乘法：执行乘法运算并返回是否溢出
    /// 参数：n1 - 第一个操作数，n2 - 第二个操作数
    /// 返回：(结果, 是否溢出)
    public fun overflowing_mul(n1: u128, n2: u128): (u128, bool) {
        let (c0, c1) = full_mul(n1, n2);
        if (c1 > 0) {
            (c0, true)
        } else {
            (c0, false)
        }
    }

    /// 完整乘法：执行乘法运算并返回完整的256位结果
    /// 参数：n1 - 第一个操作数，n2 - 第二个操作数
    /// 返回：(低128位, 高128位)
    public fun full_mul(n1: u128, n2: u128): (u128, u128) {
        let hi_mask: u256 =
            0xffffffffffffffffffffffffffffffff00000000000000000000000000000000;
        let lo_mask: u256 =
            0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;
        let r = (n1 as u256) * (n2 as u256);
        let hi = (((r & hi_mask) >> 128) as u128);
        let lo = ((r & lo_mask) as u128);
        (lo, hi)
    }

    /// 提取128位数字的高64位
    /// 参数：n - 输入的128位数字
    /// 返回：高64位作为u64
    public fun hi(n: u128): u64 {
        (((n & HI_64_MASK) >> 64) as u64)
    }

    /// 提取128位数字的低64位
    /// 参数：n - 输入的128位数字
    /// 返回：低64位作为u64
    public fun lo(n: u128): u64 {
        ((n & LO_64_MASK) as u64)
    }

    /// 提取128位数字的高64位（返回u128）
    /// 参数：n - 输入的128位数字
    /// 返回：高64位作为u128
    public fun hi_u128(n: u128): u128 {
        (n & HI_64_MASK) >> 64
    }

    /// 提取128位数字的低64位（返回u128）
    /// 参数：n - 输入的128位数字
    /// 返回：低64位作为u128
    public fun lo_u128(n: u128): u128 {
        (n & LO_64_MASK)
    }

    /// 从低位和高位构造128位数字
    /// 参数：lo - 低64位，hi - 高64位
    /// 返回：构造的128位数字
    public fun from_lo_hi(lo: u64, hi: u64): u128 {
        ((hi as u128) << 64) + (lo as u128)
    }

    /// 带舍入的除法：执行除法运算，支持向上舍入
    /// 参数：num - 被除数，denom - 除数，round_up - 是否向上舍入
    /// 返回：除法结果
    public fun checked_div_round(num: u128, denom: u128, round_up: bool): u128 {
        if (denom == 0) {
            abort DIV_BY_ZERO
        };
        let quotient = num / denom;
        let remainer = num % denom;
        if (round_up && (remainer > 0)) {
            return (quotient + 1)
        };
        quotient
    }

    /// 求两个数的最大值
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：较大的数
    public fun max(num1: u128, num2: u128): u128 {
        if (num1 > num2) { num1 }
        else { num2 }
    }

    /// 求两个数的最小值
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：较小的数
    public fun min(num1: u128, num2: u128): u128 {
        if (num1 < num2) { num1 }
        else { num2 }
    }

    /// 检查加法是否会溢出
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：如果不会溢出返回true，否则返回false
    public fun add_check(num1: u128, num2: u128): bool {
        (MAX_U128 - num1 >= num2)
    }

    #[test]
    fun test_overflowing_add() {
        let (m, o) = overflowing_add(10, 10);
        assert!(m == 20u128 && o == false, 0);

        let (m, o) = overflowing_add(MAX_U128, 10);
        assert!(m == 9u128 && o == true, 0);
    }

    #[test]
    fun test_full_mul() {
        let (lo, hi) = full_mul(0, 10);
        assert!(hi == 0 && lo == 0, 0);

        let (lo, hi) = full_mul(10, 10);
        assert!(hi == 0 && lo == 100, 0);

        let (lo, hi) = full_mul(9999, 10);
        assert!(hi == 0 && lo == 99990, 0);

        let (lo, hi) = full_mul(MAX_U128, 0);
        assert!(hi == 0 && lo == 0, 0);

        let (lo, hi) = full_mul(MAX_U128, 1);
        assert!(hi == 0 && lo == MAX_U128, 0);

        let (lo, hi) = full_mul(MAX_U128, 10);
        assert!(
            hi == 9 && lo == 0xfffffffffffffffffffffffffffffff6,
            0
        );

        let (lo, hi) = full_mul(10, MAX_U128);
        assert!(
            hi == 9 && lo == 0xfffffffffffffffffffffffffffffff6,
            0
        );

        let (lo, hi) = full_mul(MAX_U128, MAX_U128);
        assert!(
            hi == 0xfffffffffffffffffffffffffffffffe && lo == 1,
            0
        );
    }

    #[test]
    fun test_wrapping_mul() {
        assert!(wrapping_mul(0, 10) == 0, 0);
        assert!(wrapping_mul(10, 0) == 0, 0);
        assert!(wrapping_mul(10, 10) == 100, 0);
        assert!(wrapping_mul(99999, 10) == 10 * 99999, 0);
        assert!(wrapping_mul(MAX_U128, 0) == 0, 0);
        assert!(wrapping_mul(MAX_U128, 1) == MAX_U128, 0);
        assert!(wrapping_mul(MAX_U128, 10) == 0xfffffffffffffffffffffffffffffff6, 0);
        assert!(wrapping_mul(10, MAX_U128) == 0xfffffffffffffffffffffffffffffff6, 0);
        assert!(wrapping_mul(MAX_U128, MAX_U128) == 1, 0);
    }

    #[test]
    fun test_overflowing_mul() {
        let (r, o) = overflowing_mul(0, 10);
        assert!(r == 0 && o == false, 0);

        let (r, o) = overflowing_mul(10, 10);
        assert!(r == 100 && o == false, 0);

        let (r, o) = overflowing_mul(MAX_U128, 10);
        assert!(
            r == 0xfffffffffffffffffffffffffffffff6 && o == true,
            0
        );
    }
}
