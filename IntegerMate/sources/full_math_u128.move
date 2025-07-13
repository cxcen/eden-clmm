/// 128位无符号整数完整数学运算模块
/// 提供了高精度的乘法和除法运算，使用256位中间结果来避免溢出
module integer_mate::full_math_u128 {
    use integer_mate::u256;
    use integer_mate::math_u128;

    /// 乘法除法（向下舍入）：执行 (num1 * num2) / denom 运算
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数，denom - 除数
    /// 返回：运算结果（向下舍入）
    public fun mul_div_floor(num1: u128, num2: u128, denom: u128): u128 {
        let r = full_mul_v2(num1, num2) / (denom as u256);
        (r as u128)
    }

    /// 乘法除法（四舍五入）：执行 (num1 * num2) / denom 运算
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数，denom - 除数
    /// 返回：运算结果（四舍五入）
    public fun mul_div_round(num1: u128, num2: u128, denom: u128): u128 {
        let r = (full_mul_v2(num1, num2) + ((denom as u256) >> 1)) / (denom as u256);
        (r as u128)
    }

    /// 乘法除法（向上舍入）：执行 (num1 * num2) / denom 运算
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数，denom - 除数
    /// 返回：运算结果（向上舍入）
    public fun mul_div_ceil(num1: u128, num2: u128, denom: u128): u128 {
        let r = (full_mul_v2(num1, num2) + ((denom as u256) - 1)) / (denom as u256);
        (r as u128)
    }

    /// 乘法右移：执行 (num1 * num2) >> shift 运算
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数，shift - 右移位数
    /// 返回：运算结果
    public fun mul_shr(num1: u128, num2: u128, shift: u8): u128 {
        let product = full_mul_v2(num1, num2) >> shift;
        (product as u128)
    }

    /// 乘法左移：执行 (num1 * num2) << shift 运算
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数，shift - 左移位数
    /// 返回：运算结果
    public fun mul_shl(num1: u128, num2: u128, shift: u8): u128 {
        let product = full_mul_v2(num1, num2) << shift;
        (product as u128)
    }

    /// 完整乘法（版本1）：执行两个u128数字的乘法，返回U256结果
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数
    /// 返回：U256乘法结果
    public fun full_mul(num1: u128, num2: u128): u256::U256 {
        let (lo, hi) = math_u128::full_mul(num1, num2);
        u256::new(
            math_u128::lo(lo),
            math_u128::hi(lo),
            math_u128::lo(hi),
            math_u128::hi(hi)
        )
    }

    /// 完整乘法（版本2）：执行两个u128数字的乘法，返回u256结果
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数
    /// 返回：u256乘法结果
    public fun full_mul_v2(num1: u128, num2: u128): u256 {
        (num1 as u256) * (num2 as u256)
    }
}
