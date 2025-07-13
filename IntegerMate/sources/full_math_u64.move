/// 64位无符号整数完整数学运算模块
/// 提供了高精度的乘法和除法运算，使用128位中间结果来避免溢出
module integer_mate::full_math_u64 {
    /// 乘法除法（向下舍入）：执行 (num1 * num2) / denom 运算
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数，denom - 除数
    /// 返回：运算结果（向下舍入）
    public fun mul_div_floor(num1: u64, num2: u64, denom: u64): u64 {
        let r = full_mul(num1, num2) / (denom as u128);
        (r as u64)
    }

    /// 乘法除法（四舍五入）：执行 (num1 * num2) / denom 运算
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数，denom - 除数
    /// 返回：运算结果（四舍五入）
    public fun mul_div_round(num1: u64, num2: u64, denom: u64): u64 {
        let r = (full_mul(num1, num2) + ((denom as u128) >> 1)) / (denom as u128);
        (r as u64)
    }

    /// 乘法除法（向上舍入）：执行 (num1 * num2) / denom 运算
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数，denom - 除数
    /// 返回：运算结果（向上舍入）
    public fun mul_div_ceil(num1: u64, num2: u64, denom: u64): u64 {
        let r = (full_mul(num1, num2) + ((denom as u128) - 1)) / (denom as u128);
        (r as u64)
    }

    /// 乘法右移：执行 (num1 * num2) >> shift 运算
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数，shift - 右移位数
    /// 返回：运算结果
    public fun mul_shr(num1: u64, num2: u64, shift: u8): u64 {
        let r = full_mul(num1, num2) >> shift;
        (r as u64)
    }

    /// 乘法左移：执行 (num1 * num2) << shift 运算
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数，shift - 左移位数
    /// 返回：运算结果
    public fun mul_shl(num1: u64, num2: u64, shift: u8): u64 {
        let r = full_mul(num1, num2) << shift;
        (r as u64)
    }

    /// 完整乘法：执行两个u64数字的乘法，返回128位结果
    /// 参数：num1 - 第一个乘数，num2 - 第二个乘数
    /// 返回：128位乘法结果
    public fun full_mul(num1: u64, num2: u64): u128 {
        ((num1 as u128) * (num2 as u128))
    }
}
