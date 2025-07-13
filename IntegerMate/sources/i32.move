/// 32位有符号整数模块
/// 提供了完整的有符号整数算术运算，包括溢出检查和符号处理
module integer_mate::i32 {
    /// 溢出错误代码
    const EOverflow: u64 = 0;

    /// 32位有符号整数的最小值对应的无符号表示
    const MIN_AS_U32: u32 = 1 << 31;
    /// 32位有符号整数的最大值对应的无符号表示
    const MAX_AS_U32: u32 = 0x7fffffff;

    /// 比较结果常量：小于
    const LT: u8 = 0;
    /// 比较结果常量：等于
    const EQ: u8 = 1;
    /// 比较结果常量：大于
    const GT: u8 = 2;

    /// 32位有符号整数结构体
    struct I32 has copy, drop, store {
        bits: u32 // 内部使用32位无符号整数存储
    }

    /// 创建零值
    /// 返回：值为0的I32
    public fun zero(): I32 {
        I32 { bits: 0 }
    }

    /// 从u32创建I32（不检查范围）
    /// 参数：v - 32位无符号整数
    /// 返回：对应的I32值
    public fun from_u32(v: u32): I32 {
        I32 { bits: v }
    }

    /// 从u32创建正数I32（检查范围）
    /// 参数：v - 32位无符号整数
    /// 返回：对应的I32值
    public fun from(v: u32): I32 {
        assert!(v <= MAX_AS_U32, EOverflow);
        I32 { bits: v }
    }

    /// 从u32创建负数I32
    /// 参数：v - 32位无符号整数（表示负数的绝对值）
    /// 返回：对应的负数I32值
    public fun neg_from(v: u32): I32 {
        assert!(v <= MIN_AS_U32, EOverflow);
        if (v == 0) {
            I32 { bits: v }
        } else {
            I32 {
                bits: (u32_neg(v) + 1) | (1 << 31)
            }
        }
    }

    /// 环绕加法：执行加法运算，不检查溢出
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：加法结果
    public fun wrapping_add(num1: I32, num2: I32): I32 {
        let sum = num1.bits ^ num2.bits;
        let carry = (num1.bits & num2.bits) << 1;
        while (carry != 0) {
            let a = sum;
            let b = carry;
            sum = a ^ b;
            carry = (a & b) << 1;
        };
        I32 { bits: sum }
    }

    /// 安全加法：执行加法运算，检查溢出
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：加法结果
    public fun add(num1: I32, num2: I32): I32 {
        let sum = wrapping_add(num1, num2);
        let overflow =
            (sign(num1) & sign(num2) & u8_neg(sign(sum)))
                + (u8_neg(sign(num1)) & u8_neg(sign(num2)) & sign(sum));
        assert!(overflow == 0, EOverflow);
        sum
    }

    /// 环绕减法：执行减法运算，不检查溢出
    /// 参数：num1 - 被减数，num2 - 减数
    /// 返回：减法结果
    public fun wrapping_sub(num1: I32, num2: I32): I32 {
        let sub_num = wrapping_add(I32 { bits: u32_neg(num2.bits) }, from(1));
        wrapping_add(num1, sub_num)
    }

    /// 安全减法：执行减法运算，检查溢出
    /// 参数：num1 - 被减数，num2 - 减数
    /// 返回：减法结果
    public fun sub(num1: I32, num2: I32): I32 {
        let v = wrapping_sub(num1, num2);
        let overflow = sign(num1) != sign(num2) && sign(num1) != sign(v);
        assert!(!overflow, EOverflow);
        v
    }

    /// 乘法：执行乘法运算
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：乘法结果
    public fun mul(num1: I32, num2: I32): I32 {
        let product = abs_u32(num1) * abs_u32(num2);
        if (sign(num1) != sign(num2)) {
            return neg_from(product)
        };
        return from(product)
    }

    /// 除法：执行除法运算
    /// 参数：num1 - 被除数，num2 - 除数
    /// 返回：除法结果
    public fun div(num1: I32, num2: I32): I32 {
        let result = abs_u32(num1) / abs_u32(num2);
        if (sign(num1) != sign(num2)) {
            return neg_from(result)
        };
        return from(result)
    }

    /// 取绝对值
    /// 参数：v - 输入的I32值
    /// 返回：绝对值
    public fun abs(v: I32): I32 {
        if (sign(v) == 0) { v }
        else {
            assert!(v.bits > MIN_AS_U32, EOverflow);
            I32 { bits: u32_neg(v.bits - 1) }
        }
    }

    /// 取绝对值（返回u32）
    /// 参数：v - 输入的I32值
    /// 返回：绝对值（u32）
    public fun abs_u32(v: I32): u32 {
        if (sign(v) == 0) { v.bits }
        else {
            u32_neg(v.bits - 1)
        }
    }

    /// 左移：执行左移运算
    /// 参数：v - 输入值，shift - 左移位数
    /// 返回：左移结果
    public fun shl(v: I32, shift: u8): I32 {
        I32 { bits: v.bits << shift }
    }

    /// 右移：执行算术右移运算
    /// 参数：v - 输入值，shift - 右移位数
    /// 返回：右移结果
    public fun shr(v: I32, shift: u8): I32 {
        if (shift == 0) {
            return v
        };
        let mask = 0xffffffff << (32 - shift);
        if (sign(v) == 1) {
            return I32 { bits: (v.bits >> shift) | mask }
        };
        I32 { bits: v.bits >> shift }
    }

    /// 取模：执行取模运算
    /// 参数：v - 被除数，n - 除数
    /// 返回：取模结果
    public fun mod(v: I32, n: I32): I32 {
        if (sign(v) == 1) {
            neg_from((abs_u32(v) % abs_u32(n)))
        } else {
            from((as_u32(v) % abs_u32(n)))
        }
    }

    /// 获取内部u32值
    /// 参数：v - 输入的I32值
    /// 返回：内部的u32值
    public fun as_u32(v: I32): u32 {
        v.bits
    }

    /// 获取符号位
    /// 参数：v - 输入的I32值
    /// 返回：符号位（0为正，1为负）
    public fun sign(v: I32): u8 {
        ((v.bits >> 31) as u8)
    }

    /// 判断是否为负数
    /// 参数：v - 输入的I32值
    /// 返回：如果为负数返回true，否则返回false
    public fun is_neg(v: I32): bool {
        sign(v) == 1
    }

    /// 比较两个I32值
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：比较结果（LT/EQ/GT）
    public fun cmp(num1: I32, num2: I32): u8 {
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
    public fun eq(num1: I32, num2: I32): bool {
        num1.bits == num2.bits
    }

    /// 判断是否大于
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：如果num1 > num2返回true，否则返回false
    public fun gt(num1: I32, num2: I32): bool {
        cmp(num1, num2) == GT
    }

    /// 判断是否大于等于
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：如果num1 >= num2返回true，否则返回false
    public fun gte(num1: I32, num2: I32): bool {
        cmp(num1, num2) >= EQ
    }

    /// 判断是否小于
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：如果num1 < num2返回true，否则返回false
    public fun lt(num1: I32, num2: I32): bool {
        cmp(num1, num2) == LT
    }

    /// 判断是否小于等于
    /// 参数：num1 - 第一个数，num2 - 第二个数
    /// 返回：如果num1 <= num2返回true，否则返回false
    public fun lte(num1: I32, num2: I32): bool {
        cmp(num1, num2) <= EQ
    }

    /// 按位或运算
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：按位或结果
    public fun or(num1: I32, num2: I32): I32 {
        I32 { bits: (num1.bits | num2.bits) }
    }

    /// 按位与运算
    /// 参数：num1 - 第一个操作数，num2 - 第二个操作数
    /// 返回：按位与结果
    public fun and(num1: I32, num2: I32): I32 {
        I32 { bits: (num1.bits & num2.bits) }
    }

    fun u32_neg(v: u32): u32 {
        v ^ 0xffffffff
    }

    fun u8_neg(v: u8): u8 {
        v ^ 0xff
    }

    #[test]
    fun test_from_ok() {
        assert!(as_u32(from(0)) == 0, 0);
        assert!(as_u32(from(10)) == 10, 1);
    }

    #[test]
    #[expected_failure]
    fun test_from_overflow() {
        as_u32(from(MIN_AS_U32));
        as_u32(from(0xffffffff));
    }

    #[test]
    fun test_neg_from() {
        assert!(as_u32(neg_from(0)) == 0, 0);
        assert!(as_u32(neg_from(1)) == 0xffffffff, 1);
        assert!(as_u32(neg_from(0x7fffffff)) == 0x80000001, 2);
        assert!(as_u32(neg_from(MIN_AS_U32)) == MIN_AS_U32, 2);
    }

    #[test]
    #[expected_failure]
    fun test_neg_from_overflow() {
        neg_from(0x80000001);
    }

    #[test]
    fun test_abs() {
        assert!(as_u32(from(10)) == 10u32, 0);
        assert!(as_u32(abs(neg_from(10))) == 10u32, 1);
        assert!(as_u32(abs(neg_from(0))) == 0u32, 2);
        assert!(
            as_u32(abs(neg_from(0x7fffffff))) == 0x7fffffff,
            3
        );
        assert!(as_u32(neg_from(MIN_AS_U32)) == MIN_AS_U32, 4);
    }

    #[test]
    #[expected_failure]
    fun test_abs_overflow() {
        abs(neg_from(1 << 31));
    }

    #[test]
    fun test_wrapping_add() {
        assert!(as_u32(wrapping_add(from(0), from(1))) == 1, 0);
        assert!(as_u32(wrapping_add(from(1), from(0))) == 1, 0);
        assert!(
            as_u32(wrapping_add(from(10000), from(99999))) == 109999,
            0
        );
        assert!(
            as_u32(wrapping_add(from(99999), from(10000))) == 109999,
            0
        );
        assert!(
            as_u32(wrapping_add(from(MAX_AS_U32 - 1), from(1))) == MAX_AS_U32,
            0
        );
        assert!(as_u32(wrapping_add(from(0), from(0))) == 0, 0);

        assert!(
            as_u32(wrapping_add(neg_from(0), neg_from(0))) == 0,
            1
        );
        assert!(
            as_u32(wrapping_add(neg_from(1), neg_from(0))) == 0xffffffff,
            1
        );
        assert!(
            as_u32(wrapping_add(neg_from(0), neg_from(1))) == 0xffffffff,
            1
        );
        assert!(
            as_u32(
                wrapping_add(neg_from(10000), neg_from(99999))
            ) == 0xfffe5251,
            1
        );
        assert!(
            as_u32(
                wrapping_add(neg_from(99999), neg_from(10000))
            ) == 0xfffe5251,
            1
        );
        assert!(
            as_u32(
                wrapping_add(neg_from(MIN_AS_U32 - 1), neg_from(1))
            ) == MIN_AS_U32,
            1
        );

        assert!(
            as_u32(wrapping_add(from(0), neg_from(0))) == 0,
            2
        );
        assert!(
            as_u32(wrapping_add(neg_from(0), from(0))) == 0,
            2
        );
        assert!(
            as_u32(wrapping_add(neg_from(1), from(1))) == 0,
            2
        );
        assert!(
            as_u32(wrapping_add(from(1), neg_from(1))) == 0,
            2
        );
        assert!(
            as_u32(wrapping_add(from(10000), neg_from(99999))) == 0xfffea071,
            2
        );
        assert!(
            as_u32(wrapping_add(from(99999), neg_from(10000))) == 89999,
            2
        );
        assert!(
            as_u32(wrapping_add(neg_from(MIN_AS_U32), from(1))) == 0x80000001,
            2
        );
        assert!(
            as_u32(wrapping_add(from(MAX_AS_U32), neg_from(1))) == MAX_AS_U32 - 1,
            2
        );

        assert!(
            as_u32(wrapping_add(from(MAX_AS_U32), from(1))) == MIN_AS_U32,
            2
        );
    }

    #[test]
    fun test_add() {
        assert!(as_u32(add(from(0), from(0))) == 0, 0);
        assert!(as_u32(add(from(0), from(1))) == 1, 0);
        assert!(as_u32(add(from(1), from(0))) == 1, 0);
        assert!(
            as_u32(add(from(10000), from(99999))) == 109999,
            0
        );
        assert!(
            as_u32(add(from(99999), from(10000))) == 109999,
            0
        );
        assert!(
            as_u32(add(from(MAX_AS_U32 - 1), from(1))) == MAX_AS_U32,
            0
        );

        assert!(as_u32(add(neg_from(0), neg_from(0))) == 0, 1);
        assert!(
            as_u32(add(neg_from(1), neg_from(0))) == 0xffffffff,
            1
        );
        assert!(
            as_u32(add(neg_from(0), neg_from(1))) == 0xffffffff,
            1
        );
        assert!(
            as_u32(add(neg_from(10000), neg_from(99999))) == 0xfffe5251,
            1
        );
        assert!(
            as_u32(add(neg_from(99999), neg_from(10000))) == 0xfffe5251,
            1
        );
        assert!(
            as_u32(add(neg_from(MIN_AS_U32 - 1), neg_from(1))) == MIN_AS_U32,
            1
        );

        assert!(as_u32(add(from(0), neg_from(0))) == 0, 2);
        assert!(as_u32(add(neg_from(0), from(0))) == 0, 2);
        assert!(as_u32(add(neg_from(1), from(1))) == 0, 2);
        assert!(as_u32(add(from(1), neg_from(1))) == 0, 2);
        assert!(
            as_u32(add(from(10000), neg_from(99999))) == 0xfffea071,
            2
        );
        assert!(
            as_u32(add(from(99999), neg_from(10000))) == 89999,
            2
        );
        assert!(
            as_u32(add(neg_from(MIN_AS_U32), from(1))) == 0x80000001,
            2
        );
        assert!(
            as_u32(add(from(MAX_AS_U32), neg_from(1))) == MAX_AS_U32 - 1,
            2
        );
    }

    #[test]
    #[expected_failure]
    fun test_add_overflow() {
        add(from(MAX_AS_U32), from(1));
    }

    #[test]
    #[expected_failure]
    fun test_add_underflow() {
        add(neg_from(MIN_AS_U32), neg_from(1));
    }

    #[test]
    fun test_wrapping_sub() {
        assert!(as_u32(wrapping_sub(from(0), from(0))) == 0, 0);
        assert!(as_u32(wrapping_sub(from(1), from(0))) == 1, 0);
        assert!(
            as_u32(wrapping_sub(from(0), from(1))) == as_u32(neg_from(1)),
            0
        );
        assert!(
            as_u32(wrapping_sub(from(1), from(1))) == as_u32(neg_from(0)),
            0
        );
        assert!(
            as_u32(wrapping_sub(from(1), neg_from(1))) == as_u32(from(2)),
            0
        );
        assert!(
            as_u32(wrapping_sub(neg_from(1), from(1))) == as_u32(neg_from(2)),
            0
        );
        assert!(
            as_u32(wrapping_sub(from(1000000), from(1))) == 999999,
            0
        );
        assert!(
            as_u32(wrapping_sub(neg_from(1000000), neg_from(1)))
                == as_u32(neg_from(999999)),
            0
        );
        assert!(
            as_u32(wrapping_sub(from(1), from(1000000))) == as_u32(neg_from(999999)),
            0
        );
        assert!(
            as_u32(
                wrapping_sub(from(MAX_AS_U32), from(MAX_AS_U32))
            ) == as_u32(from(0)),
            0
        );
        assert!(
            as_u32(wrapping_sub(from(MAX_AS_U32), from(1)))
                == as_u32(from(MAX_AS_U32 - 1)),
            0
        );
        assert!(
            as_u32(wrapping_sub(from(MAX_AS_U32), neg_from(1)))
                == as_u32(neg_from(MIN_AS_U32)),
            0
        );
        assert!(
            as_u32(
                wrapping_sub(neg_from(MIN_AS_U32), neg_from(1))
            ) == as_u32(neg_from(MIN_AS_U32 - 1)),
            0
        );
        assert!(
            as_u32(wrapping_sub(neg_from(MIN_AS_U32), from(1)))
                == as_u32(from(MAX_AS_U32)),
            0
        );
    }

    #[test]
    fun test_sub() {
        assert!(as_u32(sub(from(0), from(0))) == 0, 0);
        assert!(as_u32(sub(from(1), from(0))) == 1, 0);
        assert!(
            as_u32(sub(from(0), from(1))) == as_u32(neg_from(1)),
            0
        );
        assert!(
            as_u32(sub(from(1), from(1))) == as_u32(neg_from(0)),
            0
        );
        assert!(
            as_u32(sub(from(1), neg_from(1))) == as_u32(from(2)),
            0
        );
        assert!(
            as_u32(sub(neg_from(1), from(1))) == as_u32(neg_from(2)),
            0
        );
        assert!(
            as_u32(sub(from(1000000), from(1))) == 999999,
            0
        );
        assert!(
            as_u32(sub(neg_from(1000000), neg_from(1))) == as_u32(neg_from(999999)),
            0
        );
        assert!(
            as_u32(sub(from(1), from(1000000))) == as_u32(neg_from(999999)),
            0
        );
        assert!(
            as_u32(sub(from(MAX_AS_U32), from(MAX_AS_U32))) == as_u32(from(0)),
            0
        );
        assert!(
            as_u32(sub(from(MAX_AS_U32), from(1))) == as_u32(from(MAX_AS_U32 - 1)),
            0
        );
        assert!(
            as_u32(sub(neg_from(MIN_AS_U32), neg_from(1)))
                == as_u32(neg_from(MIN_AS_U32 - 1)),
            0
        );
    }

    #[test]
    #[expected_failure]
    fun test_sub_overflow() {
        sub(from(MAX_AS_U32), neg_from(1));
    }

    #[test]
    #[expected_failure]
    fun test_sub_underflow() {
        sub(neg_from(MIN_AS_U32), from(1));
    }

    #[test]
    fun test_mul() {
        assert!(as_u32(mul(from(1), from(1))) == 1, 0);
        assert!(as_u32(mul(from(10), from(10))) == 100, 0);
        assert!(as_u32(mul(from(100), from(100))) == 10000, 0);
        assert!(
            as_u32(mul(from(10000), from(10000))) == 100000000,
            0
        );

        assert!(
            as_u32(mul(neg_from(1), from(1))) == as_u32(neg_from(1)),
            0
        );
        assert!(
            as_u32(mul(neg_from(10), from(10))) == as_u32(neg_from(100)),
            0
        );
        assert!(
            as_u32(mul(neg_from(100), from(100))) == as_u32(neg_from(10000)),
            0
        );
        assert!(
            as_u32(mul(neg_from(10000), from(10000))) == as_u32(neg_from(100000000)),
            0
        );

        assert!(
            as_u32(mul(from(1), neg_from(1))) == as_u32(neg_from(1)),
            0
        );
        assert!(
            as_u32(mul(from(10), neg_from(10))) == as_u32(neg_from(100)),
            0
        );
        assert!(
            as_u32(mul(from(100), neg_from(100))) == as_u32(neg_from(10000)),
            0
        );
        assert!(
            as_u32(mul(from(10000), neg_from(10000))) == as_u32(neg_from(100000000)),
            0
        );
        assert!(
            as_u32(mul(from(MIN_AS_U32 / 2), neg_from(2))) == as_u32(neg_from(MIN_AS_U32)),
            0
        );
    }

    #[test]
    #[expected_failure]
    fun test_mul_overflow() {
        mul(from(MIN_AS_U32 / 2), from(1));
        mul(neg_from(MIN_AS_U32 / 2), neg_from(2));
    }

    #[test]
    fun test_div() {
        assert!(as_u32(div(from(0), from(1))) == 0, 0);
        assert!(as_u32(div(from(10), from(1))) == 10, 0);
        assert!(
            as_u32(div(from(10), neg_from(1))) == as_u32(neg_from(10)),
            0
        );
        assert!(
            as_u32(div(neg_from(10), neg_from(1))) == as_u32(from(10)),
            0
        );

        assert!(abs_u32(neg_from(MIN_AS_U32)) == MIN_AS_U32, 0);
        assert!(
            as_u32(div(neg_from(MIN_AS_U32), from(1))) == MIN_AS_U32,
            0
        );
    }

    #[test]
    #[expected_failure]
    fun test_div_overflow() {
        div(neg_from(MIN_AS_U32), neg_from(1));
    }

    #[test]
    fun test_shl() {
        assert!(as_u32(shl(from(10), 0)) == 10, 0);
        assert!(
            as_u32(shl(neg_from(10), 0)) == as_u32(neg_from(10)),
            0
        );

        assert!(as_u32(shl(from(10), 1)) == 20, 0);
        assert!(
            as_u32(shl(neg_from(10), 1)) == as_u32(neg_from(20)),
            0
        );

        assert!(as_u32(shl(from(10), 8)) == 2560, 0);
        assert!(
            as_u32(shl(neg_from(10), 8)) == as_u32(neg_from(2560)),
            0
        );

        assert!(as_u32(shl(from(10), 31)) == 0, 0);
        assert!(as_u32(shl(neg_from(10), 31)) == 0, 0);
    }

    #[test]
    fun test_shr() {
        assert!(as_u32(shr(from(10), 0)) == 10, 0);
        assert!(
            as_u32(shr(neg_from(10), 0)) == as_u32(neg_from(10)),
            0
        );

        assert!(as_u32(shr(from(10), 1)) == 5, 0);
        assert!(
            as_u32(shr(neg_from(10), 1)) == as_u32(neg_from(5)),
            0
        );

        assert!(
            as_u32(shr(from(MAX_AS_U32), 8)) == MAX_AS_U32 >> 8,
            0
        );
        assert!(
            as_u32(shr(neg_from(MIN_AS_U32), 8)) == 0xff800000,
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
            cmp(neg_from(MIN_AS_U32), from(MAX_AS_U32)) == LT,
            0
        );
        assert!(
            cmp(from(MAX_AS_U32), neg_from(MIN_AS_U32)) == GT,
            0
        );

        assert!(
            cmp(from(MAX_AS_U32), from(MAX_AS_U32 - 1)) == GT,
            0
        );
        assert!(
            cmp(from(MAX_AS_U32 - 1), from(MAX_AS_U32)) == LT,
            0
        );

        assert!(
            cmp(neg_from(MIN_AS_U32), neg_from(MIN_AS_U32 - 1)) == LT,
            0
        );
        assert!(
            cmp(neg_from(MIN_AS_U32 - 1), neg_from(MIN_AS_U32)) == GT,
            0
        );
    }

    #[test]
    fun test_castdown() {
        assert!((1u32 as u8) == 1u8, 0);
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
