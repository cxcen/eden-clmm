/// 工具函数模块
/// 提供了常用的辅助函数，如字符串转换和类型比较
module eden_clmm::utils {
    use std::vector;
    use aptos_std::comparator;
    use std::string::{Self, String};
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::Object;

   // 将u64数字转换为字符串
   // 参数：num - 要转换的数字
   // 返回：数字的字符串表示
    public fun str(num: u64): String {
        if (num == 0) {
            return string::utf8(b"0")
        };
        let remainder: u8;
        let digits = vector::empty<u8>();
        while (num > 0) {
            remainder = (num % 10 as u8);
            num = num / 10;
            digits.push_back(remainder + 48); // 48是ASCII码中'0'的值
        };
        digits.reverse(); // 反转数字顺序，从高位到低位
        string::utf8(digits)
    }

   // 比较两个币种类型的大小
   // 参数：CoinTypeA - 第一个币种类型，CoinTypeB - 第二个币种类型
   // 返回：比较结果（用于确定币种对的顺序）
    public fun compare_coin(token_a: Object<Metadata>, token_b: Object<Metadata>,): comparator::Result {
        comparator::compare(&token_a, &token_b)
    }
}
