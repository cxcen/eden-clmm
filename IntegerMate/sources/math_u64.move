/// 64位无符号整数数学运算模块
/// 提供了安全的算术运算，包括溢出检查和进位处理
module integer_mate::math_u64 {
    /// 64位无符号整数的最大值
    const MAX_U64: u64 = 0xffffffffffffffff;

    /// 高64位掩码，用于提取128位数字的高64位
    const HI_64_MASK: u128 = 0xffffffffffffffff0000000000000000;
    /// 低64位掩码，用于提取128位数字的低64位
    const LO_64_MASK: u128 = 0x0000000000000000ffffffffffffffff;

    /// 环绕加法：执行加法运算，如果溢出则环绕
    /// 参数：n1 - 第一个操作数，n2 - 第二个操作数
    /// 返回：加法结果（溢出时环绕）
    public fun wrapping_add(n1: u64, n2: u64): u64 {
        let (sum, _) = overflowing_add(n1, n2);
        sum
    }

    /// 溢出检查加法：执行加法运算并返回是否溢出
    /// 参数：n1 - 第一个操作数，n2 - 第二个操作数
    /// 返回：(结果, 是否溢出)
    public fun overflowing_add(n1: u64, n2: u64): (u64, bool) {
        let sum = (n1 as u128) + (n2 as u128);
        if (sum > (MAX_U64 as u128)) {
            (((sum & LO_64_MASK) as u64), true)
        } else {
            ((sum as u64), false)
        }
    }

    /// 环绕减法：执行减法运算，如果溢出则环绕
    /// 参数：n1 - 被减数，n2 - 减数
    /// 返回：减法结果（溢出时环绕）
    public fun wrapping_sub(n1: u64, n2: u64): u64 {
        let (result, _) = overflowing_sub(n1, n2);
        result
    }

    /// 溢出检查减法：执行减法运算并返回是否溢出
    /// 参数：n1 - 被减数，n2 - 减数
    /// 返回：(结果, 是否溢出)
    public fun overflowing_sub(n1: u64, n2: u64): (u64, bool) {
        if (n1 >= n2) {
            ((n1 - n2), false)
        } else {
            ((MAX_U64 - n2 + n1 + 1), true)
        }
    }

    /// 环绕乘法：执行乘法运算，如果溢出则环绕
    /// 参数：n1 - 第一个操作数，n2 - 第二个操作数
    /// 返回：乘法结果（溢出时环绕）
    public fun wrapping_mul(n1: u64, n2: u64): u64 {
        let (m, _) = overflowing_mul(n1, n2);
        m
    }

    /// 溢出检查乘法：执行乘法运算并返回是否溢出
    /// 参数：n1 - 第一个操作数，n2 - 第二个操作数
    /// 返回：(结果, 是否溢出)
    public fun overflowing_mul(n1: u64, n2: u64): (u64, bool) {
        let m = (n1 as u128) * (n2 as u128);
        (((m & LO_64_MASK) as u64), (m & HI_64_MASK) > 0)
    }

    /// 带进位的加法：执行加法运算并处理进位
    /// 参数：n1 - 第一个操作数，n2 - 第二个操作数，carry - 进位值（0或1）
    /// 返回：(结果, 输出进位)
    public fun carry_add(n1: u64, n2: u64, carry: u64): (u64, u64) {
        assert!(carry <= 1, 0);
        let sum = (n1 as u128) + (n2 as u128) + (carry as u128);
        if (sum > LO_64_MASK) {
            (((sum & LO_64_MASK) as u64), 1)
        } else {
            ((sum as u64), 0)
        }
    }

    /// 检查加法是否会溢出
    /// 参数：n1 - 第一个操作数，n2 - 第二个操作数
    /// 返回：如果不会溢出返回true，否则返回false
    public fun add_check(n1: u64, n2: u64): bool {
        (MAX_U64 - n1 >= n2)
    }
}
