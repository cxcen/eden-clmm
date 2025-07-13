/// 128位有符号整数模块
/// 提供了完整的有符号整数算术运算，包括溢出检查和符号处理
/// 这个模块在DEX中用于处理大数值的计算，如流动性变化量等
module integer_mate::i128 {
    use std::error;
    use integer_mate::i64;
    use integer_mate::i32;

    /// 溢出错误代码
    const OVERFLOW: u64 = 0;

    /// 128位有符号整数的最小值对应的无符号表示（-2^127）
    const MIN_AS_U128: u128 = 1 << 127;
    /// 128位有符号整数的最大值对应的无符号表示（2^127-1）
    const MAX_AS_U128: u128 = 0x7fffffffffffffffffffffffffffffff;

    /// 比较结果常量：小于
    const LT: u8 = 0;
    /// 比较结果常量：等于
    const EQ: u8 = 1;
    /// 比较结果常量：大于
    const GT: u8 = 2;

    /// 128位有符号整数结构体
    struct I128 has copy, drop, store {
        bits: u128 // 内部使用128位无符号整数存储，使用二进制补码表示
    }

    /// 创建零值
    /// 返回：值为0的I128
    public fun zero(): I128 {
        I128 { bits: 0 }
    }

    /// 从u128创建正数I128（检查范围）
    /// 参数：v - 128位无符号整数
    /// 返回：对应的I128值
    public fun from(v: u128): I128 {
        assert!(v <= MAX_AS_U128, error::invalid_argument(OVERFLOW));
        I128 { bits: v }
    }

    /// 从u128创建负数I128
    /// 参数：v - 128位无符号整数（表示负数的绝对值）
    /// 返回：对应的负数I128值
    public fun neg_from(v: u128): I128 {
        assert!(v <= MIN_AS_U128, error::invalid_argument(OVERFLOW));
        if (v == 0) {
            I128 { bits: v }
        } else {
            I128 {
                bits: (u128_neg(v) + 1) | (1 << 127)
            }
        }
    }

    /// 取负数：将I128值取负
    /// 参数：v - 输入的I128值
    /// 返回：取负后的I128值
    public fun neg(v: I128): I128 {
        if (is_neg(v)) { abs(v) }
        else {
            neg_from(v.bits)
        }
    }

    /// 环绕加法：执行加法运算，不检查溢出
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：加法结果
    public fun wrapping_add(num1: I128, num2: I128): I128 {
        let sum = num1.bits ^ num2.bits;
        let carry = (num1.bits & num2.bits) << 1;
        while (carry != 0) {
            let a = sum;
            let b = carry;
            sum = a ^ b;
            carry = (a & b) << 1;
        };
        I128 { bits: sum }
    }

    /// 安全加法：执行加法运算，检查溢出
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：加法结果
    public fun add(num1: I128, num2: I128): I128 {
        let sum = wrapping_add(num1, num2);
        let overflow =
            (sign(num1) & sign(num2) & u8_neg(sign(sum)))
                + (u8_neg(sign(num1)) & u8_neg(sign(num2)) & sign(sum));
        assert!(overflow == 0, error::invalid_argument(OVERFLOW));
        sum
    }

    /// 溢出检查加法：执行加法运算并返回是否溢出
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：(结果, 是否溢出)
    public fun overflowing_add(num1: I128, num2: I128): (I128, bool) {
        let sum = wrapping_add(num1, num2);
        let overflow =
            (sign(num1) & sign(num2) & u8_neg(sign(sum)))
                + (u8_neg(sign(num1)) & u8_neg(sign(num2)) & sign(sum));
        (sum, overflow != 0)
    }

    /// 环绕减法：执行减法运算，不检查溢出
    /// 参数：num1 - 被减数，num2 - 减数
    /// 返回：减法结果
    public fun wrapping_sub(num1: I128, num2: I128): I128 {
        let sub_num = wrapping_add(I128 { bits: u128_neg(num2.bits) }, from(1));
        wrapping_add(num1, sub_num)
    }

    /// 安全减法：执行减法运算，检查溢出
    /// 参数：num1 - 被减数，num2 - 减数
    /// 返回：减法结果
    public fun sub(num1: I128, num2: I128): I128 {
        let (v, overflow) = overflowing_sub(num1, num2);
        assert!(!overflow, OVERFLOW);
        v
    }

    /// 溢出检查减法：执行减法运算并返回是否溢出
    /// 参数：num1 - 被减数，num2 - 减数
    /// 返回：(结果, 是否溢出)
    public fun overflowing_sub(num1: I128, num2: I128): (I128, bool) {
        let v = wrapping_sub(num1, num2);
        let overflow = sign(num1) != sign(num2) && sign(num1) != sign(v);
        (v, overflow)
    }

    /// 乘法：执行乘法运算
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：乘法结果
    public fun mul(num1: I128, num2: I128): I128 {
        let product = abs_u128(num1) * abs_u128(num2);
        if (sign(num1) != sign(num2)) {
            return neg_from(product)
        };
        return from(product)
    }

    /// 除法：执行除法运算
    /// 参数：num1 - 被除数，num2 - 除数
    /// 返回：除法结果
    public fun div(num1: I128, num2: I128): I128 {
        let result = abs_u128(num1) / abs_u128(num2);
        if (sign(num1) != sign(num2)) {
            return neg_from(result)
        };
        return from(result)
    }

    /// 取绝对值
    /// 参数：v - 输入的I128值
    /// 返回：绝对值
    public fun abs(v: I128): I128 {
        if (sign(v) == 0) { v }
        else {
            assert!(v.bits > MIN_AS_U128, error::invalid_argument(OVERFLOW));
            I128 { bits: u128_neg(v.bits - 1) }
        }
    }

    /// 取绝对值（返回u128）
    /// 参数：v - 输入的I128值
    /// 返回：绝对值（u128）
    public fun abs_u128(v: I128): u128 {
        if (sign(v) == 0) { v.bits }
        else {
            u128_neg(v.bits - 1)
        }
    }

    /// 左移：执行左移运算
    /// 参数：v - 输入值，shift - 左移位数
    /// 返回：左移结果
    public fun shl(v: I128, shift: u8): I128 {
        I128 { bits: v.bits << shift }
    }

    /// 右移：执行算术右移运算（保持符号位）
    /// 参数：v - 输入值，shift - 右移位数
    /// 返回：右移结果
    public fun shr(v: I128, shift: u8): I128 {
        if (shift == 0) {
            return v
        };
        let mask = 0xffffffffffffffffffffffffffffffff << (128 - shift);
        if (sign(v) == 1) {
            return I128 { bits: (v.bits >> shift) | mask }
        };
        I128 { bits: v.bits >> shift }
    }

    /// 获取内部u128值
    /// 参数：v - 输入的I128值
    /// 返回：内部的u128值
    public fun as_u128(v: I128): u128 {
        v.bits
    }

    /// 转换为I64（可能截断）
    /// 参数：v - 输入的I128值
    /// 返回：对应的I64值
    public fun as_i64(v: I128): i64::I64 {
        if (is_neg(v)) {
            return i64::neg_from((abs_u128(v) as u64))
        } else {
            return i64::from((abs_u128(v) as u64))
        }
    }

    /// 转换为I32（可能截断）
    /// 参数：v - 输入的I128值
    /// 返回：对应的I32值
    public fun as_i32(v: I128): i32::I32 {
        if (is_neg(v)) {
            return i32::neg_from((abs_u128(v) as u32))
        } else {
            return i32::from((abs_u128(v) as u32))
        }
    }

    /// 获取符号位
    /// 参数：v - 输入的I128值
    /// 返回：符号位（0为正，1为负）
    public fun sign(v: I128): u8 {
        ((v.bits >> 127) as u8)
    }

    /// 判断是否为负数
    /// 参数：v - 输入的I128值
    /// 返回：如果为负数返回true，否则返回false
    public fun is_neg(v: I128): bool {
        sign(v) == 1
    }

    /// 比较两个I128值
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：比较结果（LT/EQ/GT）
    public fun cmp(num1: I128, num2: I128): u8 {
        if (num1.bits == num2.bits) return EQ;
        if (sign(num1) > sign(num2)) return LT;
        if (sign(num1) < sign(num2)) return GT;
        if (num1.bits > num2.bits) {
            return GT
        } else {
            return LT
        }
    }

    /// 判断是否相等
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：如果相等返回true，否则返回false
    public fun eq(num1: I128, num2: I128): bool {
        num1.bits == num2.bits
    }

    /// 判断是否大于
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：如果num1 > num2返回true，否则返回false
    public fun gt(num1: I128, num2: I128): bool {
        cmp(num1, num2) == GT
    }

    public fun gte(num1: I128, num2: I128): bool {
        cmp(num1, num2) >= EQ
    }

    public fun lt(num1: I128, num2: I128): bool {
        cmp(num1, num2) == LT
    }

    public fun lte(num1: I128, num2: I128): bool {
        cmp(num1, num2) <= EQ
    }

    public fun or(num1: I128, num2: I128): I128 {
        I128 { bits: (num1.bits | num2.bits) }
    }

    public fun and(num1: I128, num2: I128): I128 {
        I128 { bits: (num1.bits & num2.bits) }
    }

    fun u128_neg(v: u128): u128 {
        v ^ 0xffffffffffffffffffffffffffffffff
    }

    fun u8_neg(v: u8): u8 {
        v ^ 0xff
    }

    #[test]
    fun test_from_ok() {
        assert!(as_u128(from(0)) == 0, 0);
        assert!(as_u128(from(10)) == 10, 1);
    }

    #[test]
    #[expected_failure]
    fun test_from_overflow() {
        as_u128(from(MIN_AS_U128));
        as_u128(from(0xffffffffffffffffffffffffffffffff));
    }

    #[test]
    fun test_neg_from() {
        assert!(as_u128(neg_from(0)) == 0, 0);
        assert!(as_u128(neg_from(1)) == 0xffffffffffffffffffffffffffffffff, 1);
        assert!(
            as_u128(neg_from(0x7fffffffffffffffffffffffffffffff))
                == 0x80000000000000000000000000000001,
            2
        );
        assert!(as_u128(neg_from(MIN_AS_U128)) == MIN_AS_U128, 2);
    }

    #[test]
    #[expected_failure]
    fun test_neg_from_overflow() {
        neg_from(0x80000000000000000000000000000001);
    }

    #[test]
    fun test_abs() {
        assert!(as_u128(from(10)) == 10u128, 0);
        assert!(as_u128(abs(neg_from(10))) == 10u128, 1);
        assert!(as_u128(abs(neg_from(0))) == 0u128, 2);
        assert!(
            as_u128(abs(neg_from(0x7fffffffffffffffffffffffffffffff)))
                == 0x7fffffffffffffffffffffffffffffff,
            3
        );
        assert!(as_u128(neg_from(MIN_AS_U128)) == MIN_AS_U128, 4);
    }

    #[test]
    #[expected_failure]
    fun test_abs_overflow() {
        abs(neg_from(1 << 127));
    }

    #[test]
    fun test_wrapping_add() {
        assert!(as_u128(wrapping_add(from(0), from(1))) == 1, 0);
        assert!(as_u128(wrapping_add(from(1), from(0))) == 1, 0);
        assert!(
            as_u128(wrapping_add(from(10000), from(99999))) == 109999,
            0
        );
        assert!(
            as_u128(wrapping_add(from(99999), from(10000))) == 109999,
            0
        );
        assert!(
            as_u128(wrapping_add(from(MAX_AS_U128 - 1), from(1))) == MAX_AS_U128,
            0
        );
        assert!(as_u128(wrapping_add(from(0), from(0))) == 0, 0);

        assert!(
            as_u128(wrapping_add(neg_from(0), neg_from(0))) == 0,
            1
        );
        assert!(
            as_u128(wrapping_add(neg_from(1), neg_from(0)))
                == 0xffffffffffffffffffffffffffffffff,
            1
        );
        assert!(
            as_u128(wrapping_add(neg_from(0), neg_from(1)))
                == 0xffffffffffffffffffffffffffffffff,
            1
        );
        assert!(
            as_u128(
                wrapping_add(neg_from(10000), neg_from(99999))
            ) == 0xfffffffffffffffffffffffffffe5251,
            1
        );
        assert!(
            as_u128(
                wrapping_add(neg_from(99999), neg_from(10000))
            ) == 0xfffffffffffffffffffffffffffe5251,
            1
        );
        assert!(
            as_u128(
                wrapping_add(neg_from(MIN_AS_U128 - 1), neg_from(1))
            ) == MIN_AS_U128,
            1
        );

        assert!(
            as_u128(wrapping_add(from(0), neg_from(0))) == 0,
            2
        );
        assert!(
            as_u128(wrapping_add(neg_from(0), from(0))) == 0,
            2
        );
        assert!(
            as_u128(wrapping_add(neg_from(1), from(1))) == 0,
            2
        );
        assert!(
            as_u128(wrapping_add(from(1), neg_from(1))) == 0,
            2
        );
        assert!(
            as_u128(wrapping_add(from(10000), neg_from(99999)))
                == 0xfffffffffffffffffffffffffffea071,
            2
        );
        assert!(
            as_u128(wrapping_add(from(99999), neg_from(10000))) == 89999,
            2
        );
        assert!(
            as_u128(wrapping_add(neg_from(MIN_AS_U128), from(1)))
                == 0x80000000000000000000000000000001,
            2
        );
        assert!(
            as_u128(wrapping_add(from(MAX_AS_U128), neg_from(1))) == MAX_AS_U128 - 1,
            2
        );

        assert!(
            as_u128(wrapping_add(from(MAX_AS_U128), from(1))) == MIN_AS_U128,
            2
        );
    }

    #[test]
    fun test_add() {
        assert!(as_u128(add(from(0), from(0))) == 0, 0);
        assert!(as_u128(add(from(0), from(1))) == 1, 0);
        assert!(as_u128(add(from(1), from(0))) == 1, 0);
        assert!(
            as_u128(add(from(10000), from(99999))) == 109999,
            0
        );
        assert!(
            as_u128(add(from(99999), from(10000))) == 109999,
            0
        );
        assert!(
            as_u128(add(from(MAX_AS_U128 - 1), from(1))) == MAX_AS_U128,
            0
        );

        assert!(as_u128(add(neg_from(0), neg_from(0))) == 0, 1);
        assert!(
            as_u128(add(neg_from(1), neg_from(0))) == 0xffffffffffffffffffffffffffffffff,
            1
        );
        assert!(
            as_u128(add(neg_from(0), neg_from(1))) == 0xffffffffffffffffffffffffffffffff,
            1
        );
        assert!(
            as_u128(add(neg_from(10000), neg_from(99999)))
                == 0xfffffffffffffffffffffffffffe5251,
            1
        );
        assert!(
            as_u128(add(neg_from(99999), neg_from(10000)))
                == 0xfffffffffffffffffffffffffffe5251,
            1
        );
        assert!(
            as_u128(add(neg_from(MIN_AS_U128 - 1), neg_from(1))) == MIN_AS_U128,
            1
        );

        assert!(as_u128(add(from(0), neg_from(0))) == 0, 2);
        assert!(as_u128(add(neg_from(0), from(0))) == 0, 2);
        assert!(as_u128(add(neg_from(1), from(1))) == 0, 2);
        assert!(as_u128(add(from(1), neg_from(1))) == 0, 2);
        assert!(
            as_u128(add(from(10000), neg_from(99999)))
                == 0xfffffffffffffffffffffffffffea071,
            2
        );
        assert!(
            as_u128(add(from(99999), neg_from(10000))) == 89999,
            2
        );
        assert!(
            as_u128(add(neg_from(MIN_AS_U128), from(1)))
                == 0x80000000000000000000000000000001,
            2
        );
        assert!(
            as_u128(add(from(MAX_AS_U128), neg_from(1))) == MAX_AS_U128 - 1,
            2
        );
    }

    #[test]
    fun test_overflowing_add() {
        let (result, overflow) = overflowing_add(from(MAX_AS_U128), neg_from(1));
        assert!(
            overflow == false && as_u128(result) == MAX_AS_U128 - 1,
            1
        );
        let (_, overflow) = overflowing_add(from(MAX_AS_U128), from(1));
        assert!(overflow == true, 1);
        let (_, overflow) = overflowing_add(neg_from(MIN_AS_U128), neg_from(1));
        assert!(overflow == true, 1);
    }

    #[test]
    #[expected_failure]
    fun test_add_overflow() {
        add(from(MAX_AS_U128), from(1));
    }

    #[test]
    #[expected_failure]
    fun test_add_underflow() {
        add(neg_from(MIN_AS_U128), neg_from(1));
    }

    #[test]
    fun test_wrapping_sub() {
        assert!(as_u128(wrapping_sub(from(0), from(0))) == 0, 0);
        assert!(as_u128(wrapping_sub(from(1), from(0))) == 1, 0);
        assert!(
            as_u128(wrapping_sub(from(0), from(1))) == as_u128(neg_from(1)),
            0
        );
        assert!(
            as_u128(wrapping_sub(from(1), from(1))) == as_u128(neg_from(0)),
            0
        );
        assert!(
            as_u128(wrapping_sub(from(1), neg_from(1))) == as_u128(from(2)),
            0
        );
        assert!(
            as_u128(wrapping_sub(neg_from(1), from(1))) == as_u128(neg_from(2)),
            0
        );
        assert!(
            as_u128(wrapping_sub(from(1000000), from(1))) == 999999,
            0
        );
        assert!(
            as_u128(wrapping_sub(neg_from(1000000), neg_from(1)))
                == as_u128(neg_from(999999)),
            0
        );
        assert!(
            as_u128(wrapping_sub(from(1), from(1000000))) == as_u128(neg_from(999999)),
            0
        );
        assert!(
            as_u128(
                wrapping_sub(from(MAX_AS_U128), from(MAX_AS_U128))
            ) == as_u128(from(0)),
            0
        );
        assert!(
            as_u128(wrapping_sub(from(MAX_AS_U128), from(1)))
                == as_u128(from(MAX_AS_U128 - 1)),
            0
        );
        assert!(
            as_u128(wrapping_sub(from(MAX_AS_U128), neg_from(1)))
                == as_u128(neg_from(MIN_AS_U128)),
            0
        );
        assert!(
            as_u128(
                wrapping_sub(neg_from(MIN_AS_U128), neg_from(1))
            ) == as_u128(neg_from(MIN_AS_U128 - 1)),
            0
        );
        assert!(
            as_u128(wrapping_sub(neg_from(MIN_AS_U128), from(1)))
                == as_u128(from(MAX_AS_U128)),
            0
        );
    }

    #[test]
    fun test_sub() {
        assert!(as_u128(sub(from(0), from(0))) == 0, 0);
        assert!(as_u128(sub(from(1), from(0))) == 1, 0);
        assert!(
            as_u128(sub(from(0), from(1))) == as_u128(neg_from(1)),
            0
        );
        assert!(
            as_u128(sub(from(1), from(1))) == as_u128(neg_from(0)),
            0
        );
        assert!(
            as_u128(sub(from(1), neg_from(1))) == as_u128(from(2)),
            0
        );
        assert!(
            as_u128(sub(neg_from(1), from(1))) == as_u128(neg_from(2)),
            0
        );
        assert!(
            as_u128(sub(from(1000000), from(1))) == 999999,
            0
        );
        assert!(
            as_u128(sub(neg_from(1000000), neg_from(1))) == as_u128(neg_from(999999)),
            0
        );
        assert!(
            as_u128(sub(from(1), from(1000000))) == as_u128(neg_from(999999)),
            0
        );
        assert!(
            as_u128(sub(from(MAX_AS_U128), from(MAX_AS_U128))) == as_u128(from(0)),
            0
        );
        assert!(
            as_u128(sub(from(MAX_AS_U128), from(1))) == as_u128(from(MAX_AS_U128 - 1)),
            0
        );
        assert!(
            as_u128(sub(neg_from(MIN_AS_U128), neg_from(1)))
                == as_u128(neg_from(MIN_AS_U128 - 1)),
            0
        );
    }

    #[test]
    fun test_checked_sub() {
        let (result, overflowing) = overflowing_sub(from(MAX_AS_U128), from(1));
        assert!(
            overflowing == false && as_u128(result) == MAX_AS_U128 - 1,
            1
        );

        let (_, overflowing) = overflowing_sub(neg_from(MIN_AS_U128), from(1));
        assert!(overflowing == true, 1);

        let (_, overflowing) = overflowing_sub(from(MAX_AS_U128), neg_from(1));
        assert!(overflowing == true, 1);
    }

    #[test]
    #[expected_failure]
    fun test_sub_overflow() {
        sub(from(MAX_AS_U128), neg_from(1));
    }

    #[test]
    #[expected_failure]
    fun test_sub_underflow() {
        sub(neg_from(MIN_AS_U128), from(1));
    }

    #[test]
    fun test_mul() {
        assert!(as_u128(mul(from(1), from(1))) == 1, 0);
        assert!(as_u128(mul(from(10), from(10))) == 100, 0);
        assert!(as_u128(mul(from(100), from(100))) == 10000, 0);
        assert!(
            as_u128(mul(from(10000), from(10000))) == 100000000,
            0
        );

        assert!(
            as_u128(mul(neg_from(1), from(1))) == as_u128(neg_from(1)),
            0
        );
        assert!(
            as_u128(mul(neg_from(10), from(10))) == as_u128(neg_from(100)),
            0
        );
        assert!(
            as_u128(mul(neg_from(100), from(100))) == as_u128(neg_from(10000)),
            0
        );
        assert!(
            as_u128(mul(neg_from(10000), from(10000))) == as_u128(neg_from(100000000)),
            0
        );

        assert!(
            as_u128(mul(from(1), neg_from(1))) == as_u128(neg_from(1)),
            0
        );
        assert!(
            as_u128(mul(from(10), neg_from(10))) == as_u128(neg_from(100)),
            0
        );
        assert!(
            as_u128(mul(from(100), neg_from(100))) == as_u128(neg_from(10000)),
            0
        );
        assert!(
            as_u128(mul(from(10000), neg_from(10000))) == as_u128(neg_from(100000000)),
            0
        );
        assert!(
            as_u128(mul(from(MIN_AS_U128 / 2), neg_from(2)))
                == as_u128(neg_from(MIN_AS_U128)),
            0
        );
    }

    #[test]
    #[expected_failure]
    fun test_mul_overflow() {
        mul(from(MIN_AS_U128 / 2), from(1));
        mul(neg_from(MIN_AS_U128 / 2), neg_from(2));
    }

    #[test]
    fun test_div() {
        assert!(as_u128(div(from(0), from(1))) == 0, 0);
        assert!(as_u128(div(from(10), from(1))) == 10, 0);
        assert!(
            as_u128(div(from(10), neg_from(1))) == as_u128(neg_from(10)),
            0
        );
        assert!(
            as_u128(div(neg_from(10), neg_from(1))) == as_u128(from(10)),
            0
        );

        assert!(abs_u128(neg_from(MIN_AS_U128)) == MIN_AS_U128, 0);
        assert!(
            as_u128(div(neg_from(MIN_AS_U128), from(1))) == MIN_AS_U128,
            0
        );
    }

    #[test]
    #[expected_failure]
    fun test_div_overflow() {
        div(neg_from(MIN_AS_U128), neg_from(1));
    }

    #[test]
    fun test_shl() {
        assert!(as_u128(shl(from(10), 0)) == 10, 0);
        assert!(
            as_u128(shl(neg_from(10), 0)) == as_u128(neg_from(10)),
            0
        );

        assert!(as_u128(shl(from(10), 1)) == 20, 0);
        assert!(
            as_u128(shl(neg_from(10), 1)) == as_u128(neg_from(20)),
            0
        );

        assert!(as_u128(shl(from(10), 8)) == 2560, 0);
        assert!(
            as_u128(shl(neg_from(10), 8)) == as_u128(neg_from(2560)),
            0
        );

        assert!(as_u128(shl(from(10), 32)) == 42949672960, 0);
        assert!(
            as_u128(shl(neg_from(10), 32)) == as_u128(neg_from(42949672960)),
            0
        );

        assert!(
            as_u128(shl(from(10), 64)) == 184467440737095516160,
            0
        );
        assert!(
            as_u128(shl(neg_from(10), 64)) == as_u128(neg_from(184467440737095516160)),
            0
        );

        assert!(as_u128(shl(from(10), 127)) == 0, 0);
        assert!(as_u128(shl(neg_from(10), 127)) == 0, 0);
    }

    #[test]
    fun test_shr() {
        assert!(as_u128(shr(from(10), 0)) == 10, 0);
        assert!(
            as_u128(shr(neg_from(10), 0)) == as_u128(neg_from(10)),
            0
        );

        assert!(as_u128(shr(from(10), 1)) == 5, 0);
        assert!(
            as_u128(shr(neg_from(10), 1)) == as_u128(neg_from(5)),
            0
        );

        assert!(
            as_u128(shr(from(MAX_AS_U128), 8)) == 0x7fffffffffffffffffffffffffffff,
            0
        );
        assert!(
            as_u128(shr(neg_from(MIN_AS_U128), 8)) == 0xff800000000000000000000000000000,
            0
        );

        assert!(
            as_u128(shr(from(MAX_AS_U128), 96)) == 0x7fffffff,
            0
        );
        assert!(
            as_u128(shr(neg_from(MIN_AS_U128), 96))
                == 0xffffffffffffffffffffffff80000000,
            0
        );

        assert!(as_u128(shr(from(MAX_AS_U128), 127)) == 0, 0);
        assert!(
            as_u128(shr(neg_from(MIN_AS_U128), 127))
                == 0xffffffffffffffffffffffffffffffff,
            0
        );
    }

    #[test]
    fun test_sign() {
        assert!(sign(neg_from(10)) == 1u8, 0);
        assert!(sign(from(10)) == 0u8, 0);
    }

    #[test]
    fun test_cmp() {
        assert!(cmp(from(1), from(0)) == GT, 0);
        assert!(cmp(from(0), from(1)) == LT, 0);

        assert!(cmp(from(0), neg_from(1)) == GT, 0);
        assert!(cmp(neg_from(0), neg_from(1)) == GT, 0);
        assert!(cmp(neg_from(1), neg_from(0)) == LT, 0);

        assert!(
            cmp(neg_from(MIN_AS_U128), from(MAX_AS_U128)) == LT,
            0
        );
        assert!(
            cmp(from(MAX_AS_U128), neg_from(MIN_AS_U128)) == GT,
            0
        );

        assert!(
            cmp(from(MAX_AS_U128), from(MAX_AS_U128 - 1)) == GT,
            0
        );
        assert!(
            cmp(from(MAX_AS_U128 - 1), from(MAX_AS_U128)) == LT,
            0
        );

        assert!(
            cmp(neg_from(MIN_AS_U128), neg_from(MIN_AS_U128 - 1)) == LT,
            0
        );
        assert!(
            cmp(neg_from(MIN_AS_U128 - 1), neg_from(MIN_AS_U128)) == GT,
            0
        );
    }

    #[test]
    fun test_castdown() {
        assert!((1u128 as u8) == 1u8, 0);
    }
}
