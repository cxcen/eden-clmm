/// 256位无符号整数数学运算模块
/// 提供了256位数字的基本算术运算和位操作
module integer_mate::math_u256 {
    /// 256位无符号整数的最大值
    const MAX_U256: u256 =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// 除法和取模运算：返回商和余数
    /// 参数：num - 被除数，denom - 除数
    /// 返回：(商, 余数)
    public fun div_mod(num: u256, denom: u256): (u256, u256) {
        let p = num / denom;
        let r: u256 = num - (p * denom);
        (p, r)
    }

    /// 左移64位：将数字向左移动64位（相当于乘以2^64）
    /// 参数：n - 输入的256位数字
    /// 返回：左移64位后的结果
    public fun shlw(n: u256): u256 {
        n << 64
    }

    /// 右移64位：将数字向右移动64位（相当于除以2^64）
    /// 参数：n - 输入的256位数字
    /// 返回：右移64位后的结果
    public fun shrw(n: u256): u256 {
        n >> 64
    }

    /// 检查左移64位是否会溢出
    /// 参数：n - 输入的256位数字
    /// 返回：(左移结果, 是否溢出)
    public fun checked_shlw(n: u256): (u256, bool) {
        let mask = 1 << 192;
        if (n >= mask) {
            (0, true)
        } else {
            ((n << 64), false)
        }
    }

    /// 带舍入的除法：执行除法运算，支持向上舍入
    /// 参数：num - 被除数，denom - 除数，round_up - 是否向上舍入
    /// 返回：除法结果
    public fun div_round(num: u256, denom: u256, round_up: bool): u256 {
        let p = num / denom;
        if (round_up && ((p * denom) != num)) { p + 1 }
        else { p }
    }

    /// 检查加法是否会溢出
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：如果不会溢出返回true，否则返回false
    public fun add_check(num1: u256, num2: u256): bool {
        (MAX_U256 - num1 >= num2)
    }

    #[test]
    fun test_div_round() {
        div_round(1, 1, true);
    }

    #[test]
    fun test_add() {
        1000u256 + 1000u256;
    }
}
