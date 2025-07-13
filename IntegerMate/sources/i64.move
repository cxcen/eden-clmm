/// 64位有符号整数模块
/// 提供了完整的有符号整数算术运算，包括溢出检查和符号处理
/// 这个模块在DEX中用于表示tick索引等需要有符号数的场景
module integer_mate::i64 {
    use std::error;

    /// 溢出错误代码
    const OVERFLOW: u64 = 0;

    /// 64位有符号整数的最小值对应的无符号表示（-2^63）
    const MIN_AS_U64: u64 = 1 << 63;
    /// 64位有符号整数的最大值对应的无符号表示（2^63-1）
    const MAX_AS_U64: u64 = 0x7fffffffffffffff;

    /// 比较结果常量：小于
    const LT: u8 = 0;
    /// 比较结果常量：等于
    const EQ: u8 = 1;
    /// 比较结果常量：大于
    const GT: u8 = 2;

    /// 64位有符号整数结构体
    struct I64 has copy, drop, store {
        bits: u64 // 内部使用64位无符号整数存储，使用二进制补码表示
    }

    /// 创建零值
    /// 返回：值为0的I64
    public fun zero(): I64 {
        I64 { bits: 0 }
    }

    /// 从u64创建I64（不检查范围）
    /// 参数：v - 64位无符号整数
    /// 返回：对应的I64值
    public fun from_u64(v: u64): I64 {
        I64 { bits: v }
    }

    /// 从u64创建正数I64（检查范围）
    /// 参数：v - 64位无符号整数
    /// 返回：对应的I64值
    public fun from(v: u64): I64 {
        assert!(v <= MAX_AS_U64, error::invalid_argument(OVERFLOW));
        I64 { bits: v }
    }

    /// 从u64创建负数I64
    /// 参数：v - 64位无符号整数（表示负数的绝对值）
    /// 返回：对应的负数I64值
    public fun neg_from(v: u64): I64 {
        assert!(v <= MIN_AS_U64, error::invalid_argument(OVERFLOW));
        if (v == 0) {
            I64 { bits: v }
        } else {
            I64 {
                bits: (u64_neg(v) + 1) | (1 << 63)
            }
        }
    }

    /// 环绕加法：执行加法运算，不检查溢出
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：加法结果
    public fun wrapping_add(num1: I64, num2: I64): I64 {
        let sum = num1.bits ^ num2.bits;
        let carry = (num1.bits & num2.bits) << 1;
        while (carry != 0) {
            let a = sum;
            let b = carry;
            sum = a ^ b;
            carry = (a & b) << 1;
        };
        I64 { bits: sum }
    }

    /// 安全加法：执行加法运算，检查溢出
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：加法结果
    public fun add(num1: I64, num2: I64): I64 {
        let sum = wrapping_add(num1, num2);
        let overflow =
            (sign(num1) & sign(num2) & u8_neg(sign(sum)))
                + (u8_neg(sign(num1)) & u8_neg(sign(num2)) & sign(sum));
        assert!(overflow == 0, error::invalid_argument(OVERFLOW));
        sum
    }

    /// 环绕减法：执行减法运算，不检查溢出
    /// 参数：num1 - 被减数，num2 - 减数
    /// 返回：减法结果
    public fun wrapping_sub(num1: I64, num2: I64): I64 {
        let sub_num = wrapping_add(I64 { bits: u64_neg(num2.bits) }, from(1));
        wrapping_add(num1, sub_num)
    }

    /// 安全减法：执行减法运算，检查溢出
    /// 参数：num1 - 被减数，num2 - 减数
    /// 返回：减法结果
    public fun sub(num1: I64, num2: I64): I64 {
        let v = wrapping_sub(num1, num2);
        let overflow = sign(num1) != sign(num2) && sign(num1) != sign(v);
        assert!(!overflow, OVERFLOW);
        v
    }

    /// 乘法：执行乘法运算
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：乘法结果
    public fun mul(num1: I64, num2: I64): I64 {
        let product = abs_u64(num1) * abs_u64(num2);
        if (sign(num1) != sign(num2)) {
            return neg_from(product)
        };
        return from(product)
    }

    /// 除法：执行除法运算
    /// 参数：num1 - 被除数，num2 - 除数
    /// 返回：除法结果
    public fun div(num1: I64, num2: I64): I64 {
        let result = abs_u64(num1) / abs_u64(num2);
        if (sign(num1) != sign(num2)) {
            return neg_from(result)
        };
        return from(result)
    }

    /// 取绝对值
    /// 参数：v - 输入的I64值
    /// 返回：绝对值
    public fun abs(v: I64): I64 {
        if (sign(v) == 0) { v }
        else {
            assert!(v.bits > MIN_AS_U64, error::invalid_argument(OVERFLOW));
            I64 { bits: u64_neg(v.bits - 1) }
        }
    }

    /// 取绝对值（返回u64）
    /// 参数：v - 输入的I64值
    /// 返回：绝对值（u64）
    public fun abs_u64(v: I64): u64 {
        if (sign(v) == 0) { v.bits }
        else {
            u64_neg(v.bits - 1)
        }
    }

    /// 左移：执行左移运算
    /// 参数：v - 输入值，shift - 左移位数
    /// 返回：左移结果
    public fun shl(v: I64, shift: u8): I64 {
        I64 { bits: v.bits << shift }
    }

    /// 右移：执行算术右移运算（保持符号位）
    /// 参数：v - 输入值，shift - 右移位数
    /// 返回：右移结果
    public fun shr(v: I64, shift: u8): I64 {
        if (shift == 0) {
            return v
        };
        let mask = 0xffffffffffffffff << (64 - shift);
        if (sign(v) == 1) {
            return I64 { bits: (v.bits >> shift) | mask }
        };
        I64 { bits: v.bits >> shift }
    }

    /// 取模：执行取模运算
    /// 参数：v - 被除数，n - 除数
    /// 返回：取模结果
    public fun mod(v: I64, n: I64): I64 {
        if (sign(v) == 1) {
            neg_from((abs_u64(v) % abs_u64(n)))
        } else {
            from((as_u64(v) % abs_u64(n)))
        }
    }

    /// 获取内部u64值
    /// 参数：v - 输入的I64值
    /// 返回：内部的u64值
    public fun as_u64(v: I64): u64 {
        v.bits
    }

    /// 获取符号位
    /// 参数：v - 输入的I64值
    /// 返回：符号位（0为正，1为负）
    public fun sign(v: I64): u8 {
        ((v.bits >> 63) as u8)
    }

    /// 判断是否为负数
    /// 参数：v - 输入的I64值
    /// 返回：如果为负数返回true，否则返回false
    public fun is_neg(v: I64): bool {
        sign(v) == 1
    }

    /// 比较两个I64值
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：比较结果（LT/EQ/GT）
    public fun cmp(num1: I64, num2: I64): u8 {
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
    public fun eq(num1: I64, num2: I64): bool {
        num1.bits == num2.bits
    }

    /// 判断是否大于
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：如果num1 > num2返回true，否则返回false
    public fun gt(num1: I64, num2: I64): bool {
        cmp(num1, num2) == GT
    }

    /// 判断是否大于等于
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：如果num1 >= num2返回true，否则返回false
    public fun gte(num1: I64, num2: I64): bool {
        cmp(num1, num2) >= EQ
    }

    /// 判断是否小于
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：如果num1 < num2返回true，否则返回false
    public fun lt(num1: I64, num2: I64): bool {
        cmp(num1, num2) == LT
    }

    /// 判断是否小于等于
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：如果num1 <= num2返回true，否则返回false
    public fun lte(num1: I64, num2: I64): bool {
        cmp(num1, num2) <= EQ
    }

    /// 按位或运算
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：按位或结果
    public fun or(num1: I64, num2: I64): I64 {
        I64 { bits: (num1.bits | num2.bits) }
    }

    /// 按位与运算
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：按位与结果
    public fun and(num1: I64, num2: I64): I64 {
        I64 { bits: (num1.bits & num2.bits) }
    }

    fun u64_neg(v: u64): u64 {
        v ^ 0xffffffffffffffff
    }

    fun u8_neg(v: u8): u8 {
        v ^ 0xff
    }

    #[test]
    fun test_from_ok() {
        assert!(as_u64(from(0)) == 0, 0);
        assert!(as_u64(from(10)) == 10, 1);
    }

    #[test]
    #[expected_failure]
    fun test_from_overflow() {
        as_u64(from(MIN_AS_U64));
        as_u64(from(0xffffffffffffffff));
    }

    #[test]
    fun test_neg_from() {
        assert!(as_u64(neg_from(0)) == 0, 0);
        assert!(as_u64(neg_from(1)) == 0xffffffffffffffff, 1);
        assert!(as_u64(neg_from(0x7fffffffffffffff)) == 0x8000000000000001, 2);
        assert!(as_u64(neg_from(MIN_AS_U64)) == MIN_AS_U64, 2);
    }

    #[test]
    #[expected_failure]
    fun test_neg_from_overflow() {
        neg_from(0x8000000000000001);
    }

    #[test]
    fun test_abs() {
        assert!(as_u64(from(10)) == 10u64, 0);
        assert!(as_u64(abs(neg_from(10))) == 10u64, 1);
        assert!(as_u64(abs(neg_from(0))) == 0u64, 2);
        assert!(
            as_u64(abs(neg_from(0x7fffffffffffffff))) == 0x7fffffffffffffff,
            3
        );
        assert!(as_u64(neg_from(MIN_AS_U64)) == MIN_AS_U64, 4);
    }

    #[test]
    #[expected_failure]
    fun test_abs_overflow() {
        abs(neg_from(1 << 63));
    }

    #[test]
    fun test_wrapping_add() {
        assert!(as_u64(wrapping_add(from(0), from(1))) == 1, 0);
        assert!(as_u64(wrapping_add(from(1), from(0))) == 1, 0);
        assert!(
            as_u64(wrapping_add(from(10000), from(99999))) == 109999,
            0
        );
        assert!(
            as_u64(wrapping_add(from(99999), from(10000))) == 109999,
            0
        );
        assert!(
            as_u64(wrapping_add(from(MAX_AS_U64 - 1), from(1))) == MAX_AS_U64,
            0
        );
        assert!(as_u64(wrapping_add(from(0), from(0))) == 0, 0);

        assert!(
            as_u64(wrapping_add(neg_from(0), neg_from(0))) == 0,
            1
        );
        assert!(
            as_u64(wrapping_add(neg_from(1), neg_from(0))) == 0xffffffffffffffff,
            1
        );
        assert!(
            as_u64(wrapping_add(neg_from(0), neg_from(1))) == 0xffffffffffffffff,
            1
        );
        assert!(
            as_u64(
                wrapping_add(neg_from(10000), neg_from(99999))
            ) == 0xfffffffffffe5251,
            1
        );
        assert!(
            as_u64(
                wrapping_add(neg_from(99999), neg_from(10000))
            ) == 0xfffffffffffe5251,
            1
        );
        assert!(
            as_u64(
                wrapping_add(neg_from(MIN_AS_U64 - 1), neg_from(1))
            ) == MIN_AS_U64,
            1
        );

        assert!(
            as_u64(wrapping_add(from(0), neg_from(0))) == 0,
            2
        );
        assert!(
            as_u64(wrapping_add(neg_from(0), from(0))) == 0,
            2
        );
        assert!(
            as_u64(wrapping_add(neg_from(1), from(1))) == 0,
            2
        );
        assert!(
            as_u64(wrapping_add(from(1), neg_from(1))) == 0,
            2
        );
        assert!(
            as_u64(wrapping_add(from(10000), neg_from(99999))) == 0xfffffffffffea071,
            2
        );
        assert!(
            as_u64(wrapping_add(from(99999), neg_from(10000))) == 89999,
            2
        );
        assert!(
            as_u64(wrapping_add(neg_from(MIN_AS_U64), from(1))) == 0x8000000000000001,
            2
        );
        assert!(
            as_u64(wrapping_add(from(MAX_AS_U64), neg_from(1))) == MAX_AS_U64 - 1,
            2
        );

        assert!(
            as_u64(wrapping_add(from(MAX_AS_U64), from(1))) == MIN_AS_U64,
            2
        );
    }

    #[test]
    fun test_add() {
        assert!(as_u64(add(from(0), from(0))) == 0, 0);
        assert!(as_u64(add(from(0), from(1))) == 1, 0);
        assert!(as_u64(add(from(1), from(0))) == 1, 0);
        assert!(
            as_u64(add(from(10000), from(99999))) == 109999,
            0
        );
        assert!(
            as_u64(add(from(99999), from(10000))) == 109999,
            0
        );
        assert!(
            as_u64(add(from(MAX_AS_U64 - 1), from(1))) == MAX_AS_U64,
            0
        );

        assert!(as_u64(add(neg_from(0), neg_from(0))) == 0, 1);
        assert!(
            as_u64(add(neg_from(1), neg_from(0))) == 0xffffffffffffffff,
            1
        );
        assert!(
            as_u64(add(neg_from(0), neg_from(1))) == 0xffffffffffffffff,
            1
        );
        assert!(
            as_u64(add(neg_from(10000), neg_from(99999))) == 0xfffffffffffe5251,
            1
        );
        assert!(
            as_u64(add(neg_from(99999), neg_from(10000))) == 0xfffffffffffe5251,
            1
        );
        assert!(
            as_u64(add(neg_from(MIN_AS_U64 - 1), neg_from(1))) == MIN_AS_U64,
            1
        );

        assert!(as_u64(add(from(0), neg_from(0))) == 0, 2);
        assert!(as_u64(add(neg_from(0), from(0))) == 0, 2);
        assert!(as_u64(add(neg_from(1), from(1))) == 0, 2);
        assert!(as_u64(add(from(1), neg_from(1))) == 0, 2);
        assert!(
            as_u64(add(from(10000), neg_from(99999))) == 0xfffffffffffea071,
            2
        );
        assert!(
            as_u64(add(from(99999), neg_from(10000))) == 89999,
            2
        );
        assert!(
            as_u64(add(neg_from(MIN_AS_U64), from(1))) == 0x8000000000000001,
            2
        );
        assert!(
            as_u64(add(from(MAX_AS_U64), neg_from(1))) == MAX_AS_U64 - 1,
            2
        );
    }

    #[test]
    #[expected_failure]
    fun test_add_overflow() {
        add(from(MAX_AS_U64), from(1));
    }

    #[test]
    #[expected_failure]
    fun test_add_underflow() {
        add(neg_from(MIN_AS_U64), neg_from(1));
    }

    #[test]
    fun test_wrapping_sub() {
        assert!(as_u64(wrapping_sub(from(0), from(0))) == 0, 0);
        assert!(as_u64(wrapping_sub(from(1), from(0))) == 1, 0);
        assert!(
            as_u64(wrapping_sub(from(0), from(1))) == as_u64(neg_from(1)),
            0
        );
        assert!(
            as_u64(wrapping_sub(from(1), from(1))) == as_u64(neg_from(0)),
            0
        );
        assert!(
            as_u64(wrapping_sub(from(1), neg_from(1))) == as_u64(from(2)),
            0
        );
        assert!(
            as_u64(wrapping_sub(neg_from(1), from(1))) == as_u64(neg_from(2)),
            0
        );
        assert!(
            as_u64(wrapping_sub(from(1000000), from(1))) == 999999,
            0
        );
        assert!(
            as_u64(wrapping_sub(neg_from(1000000), neg_from(1)))
                == as_u64(neg_from(999999)),
            0
        );
        assert!(
            as_u64(wrapping_sub(from(1), from(1000000))) == as_u64(neg_from(999999)),
            0
        );
        assert!(
            as_u64(
                wrapping_sub(from(MAX_AS_U64), from(MAX_AS_U64))
            ) == as_u64(from(0)),
            0
        );
        assert!(
            as_u64(wrapping_sub(from(MAX_AS_U64), from(1)))
                == as_u64(from(MAX_AS_U64 - 1)),
            0
        );
        assert!(
            as_u64(wrapping_sub(from(MAX_AS_U64), neg_from(1)))
                == as_u64(neg_from(MIN_AS_U64)),
            0
        );
        assert!(
            as_u64(
                wrapping_sub(neg_from(MIN_AS_U64), neg_from(1))
            ) == as_u64(neg_from(MIN_AS_U64 - 1)),
            0
        );
        assert!(
            as_u64(wrapping_sub(neg_from(MIN_AS_U64), from(1)))
                == as_u64(from(MAX_AS_U64)),
            0
        );
    }

    #[test]
    fun test_sub() {
        assert!(as_u64(sub(from(0), from(0))) == 0, 0);
        assert!(as_u64(sub(from(1), from(0))) == 1, 0);
        assert!(
            as_u64(sub(from(0), from(1))) == as_u64(neg_from(1)),
            0
        );
        assert!(
            as_u64(sub(from(1), from(1))) == as_u64(neg_from(0)),
            0
        );
        assert!(
            as_u64(sub(from(1), neg_from(1))) == as_u64(from(2)),
            0
        );
        assert!(
            as_u64(sub(neg_from(1), from(1))) == as_u64(neg_from(2)),
            0
        );
        assert!(
            as_u64(sub(from(1000000), from(1))) == 999999,
            0
        );
        assert!(
            as_u64(sub(neg_from(1000000), neg_from(1))) == as_u64(neg_from(999999)),
            0
        );
        assert!(
            as_u64(sub(from(1), from(1000000))) == as_u64(neg_from(999999)),
            0
        );
        assert!(
            as_u64(sub(from(MAX_AS_U64), from(MAX_AS_U64))) == as_u64(from(0)),
            0
        );
        assert!(
            as_u64(sub(from(MAX_AS_U64), from(1))) == as_u64(from(MAX_AS_U64 - 1)),
            0
        );
        assert!(
            as_u64(sub(neg_from(MIN_AS_U64), neg_from(1)))
                == as_u64(neg_from(MIN_AS_U64 - 1)),
            0
        );
    }

    #[test]
    #[expected_failure]
    fun test_sub_overflow() {
        sub(from(MAX_AS_U64), neg_from(1));
    }

    #[test]
    #[expected_failure]
    fun test_sub_underflow() {
        sub(neg_from(MIN_AS_U64), from(1));
    }

    #[test]
    fun test_mul() {
        assert!(as_u64(mul(from(1), from(1))) == 1, 0);
        assert!(as_u64(mul(from(10), from(10))) == 100, 0);
        assert!(as_u64(mul(from(100), from(100))) == 10000, 0);
        assert!(
            as_u64(mul(from(10000), from(10000))) == 100000000,
            0
        );

        assert!(
            as_u64(mul(neg_from(1), from(1))) == as_u64(neg_from(1)),
            0
        );
        assert!(
            as_u64(mul(neg_from(10), from(10))) == as_u64(neg_from(100)),
            0
        );
        assert!(
            as_u64(mul(neg_from(100), from(100))) == as_u64(neg_from(10000)),
            0
        );
        assert!(
            as_u64(mul(neg_from(10000), from(10000))) == as_u64(neg_from(100000000)),
            0
        );

        assert!(
            as_u64(mul(from(1), neg_from(1))) == as_u64(neg_from(1)),
            0
        );
        assert!(
            as_u64(mul(from(10), neg_from(10))) == as_u64(neg_from(100)),
            0
        );
        assert!(
            as_u64(mul(from(100), neg_from(100))) == as_u64(neg_from(10000)),
            0
        );
        assert!(
            as_u64(mul(from(10000), neg_from(10000))) == as_u64(neg_from(100000000)),
            0
        );
        assert!(
            as_u64(mul(from(MIN_AS_U64 / 2), neg_from(2))) == as_u64(neg_from(MIN_AS_U64)),
            0
        );
    }

    #[test]
    #[expected_failure]
    fun test_mul_overflow() {
        mul(from(MIN_AS_U64 / 2), from(1));
        mul(neg_from(MIN_AS_U64 / 2), neg_from(2));
    }

    #[test]
    fun test_div() {
        assert!(as_u64(div(from(0), from(1))) == 0, 0);
        assert!(as_u64(div(from(10), from(1))) == 10, 0);
        assert!(
            as_u64(div(from(10), neg_from(1))) == as_u64(neg_from(10)),
            0
        );
        assert!(
            as_u64(div(neg_from(10), neg_from(1))) == as_u64(from(10)),
            0
        );

        assert!(abs_u64(neg_from(MIN_AS_U64)) == MIN_AS_U64, 0);
        assert!(
            as_u64(div(neg_from(MIN_AS_U64), from(1))) == MIN_AS_U64,
            0
        );
    }

    #[test]
    #[expected_failure]
    fun test_div_overflow() {
        div(neg_from(MIN_AS_U64), neg_from(1));
    }

    #[test]
    fun test_shl() {
        assert!(as_u64(shl(from(10), 0)) == 10, 0);
        assert!(
            as_u64(shl(neg_from(10), 0)) == as_u64(neg_from(10)),
            0
        );

        assert!(as_u64(shl(from(10), 1)) == 20, 0);
        assert!(
            as_u64(shl(neg_from(10), 1)) == as_u64(neg_from(20)),
            0
        );

        assert!(as_u64(shl(from(10), 8)) == 2560, 0);
        assert!(
            as_u64(shl(neg_from(10), 8)) == as_u64(neg_from(2560)),
            0
        );

        assert!(as_u64(shl(from(10), 32)) == 42949672960, 0);
        assert!(
            as_u64(shl(neg_from(10), 32)) == as_u64(neg_from(42949672960)),
            0
        );

        assert!(as_u64(shl(from(10), 63)) == 0, 0);
        assert!(as_u64(shl(neg_from(10), 63)) == 0, 0);
    }

    #[test]
    fun test_shr() {
        assert!(as_u64(shr(from(10), 0)) == 10, 0);
        assert!(
            as_u64(shr(neg_from(10), 0)) == as_u64(neg_from(10)),
            0
        );

        assert!(as_u64(shr(from(10), 1)) == 5, 0);
        assert!(
            as_u64(shr(neg_from(10), 1)) == as_u64(neg_from(5)),
            0
        );

        assert!(
            as_u64(shr(from(MAX_AS_U64), 8)) == 36028797018963967,
            0
        );
        assert!(
            as_u64(shr(neg_from(MIN_AS_U64), 8)) == 0xff80000000000000,
            0
        );

        assert!(
            as_u64(shr(from(MAX_AS_U64), 32)) == 2147483647,
            0
        );
        assert!(
            as_u64(shr(neg_from(MIN_AS_U64), 32)) == 0xffffffff80000000,
            0
        );

        assert!(as_u64(shr(from(MAX_AS_U64), 63)) == 0, 0);
        assert!(
            as_u64(shr(neg_from(MIN_AS_U64), 63)) == 0xffffffffffffffff,
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
            cmp(neg_from(MIN_AS_U64), from(MAX_AS_U64)) == LT,
            0
        );
        assert!(
            cmp(from(MAX_AS_U64), neg_from(MIN_AS_U64)) == GT,
            0
        );

        assert!(
            cmp(from(MAX_AS_U64), from(MAX_AS_U64 - 1)) == GT,
            0
        );
        assert!(
            cmp(from(MAX_AS_U64 - 1), from(MAX_AS_U64)) == LT,
            0
        );

        assert!(
            cmp(neg_from(MIN_AS_U64), neg_from(MIN_AS_U64 - 1)) == LT,
            0
        );
        assert!(
            cmp(neg_from(MIN_AS_U64 - 1), neg_from(MIN_AS_U64)) == GT,
            0
        );
    }

    #[test]
    fun test_castdown() {
        assert!((1u64 as u8) == 1u8, 0);
    }

    #[test]
    fun test_mod() {
        //use aptos_std::debug;
        let i = mod(neg_from(2), from(5));
        assert!(cmp(i, neg_from(2)) == EQ, 0);

        i = mod(neg_from(2), neg_from(5));
        assert!(cmp(i, neg_from(2)) == EQ, 0);

        i = mod(from(2), from(5));
        assert!(cmp(i, from(2)) == EQ, 0);

        i = mod(from(2), neg_from(5));
        assert!(cmp(i, from(2)) == EQ, 0);
    }
}
