/// 位置NFT管理模块
/// 用户位置权限由代币表示。拥有代币的用户控制该位置。
/// 每个池都有一个集合，所以该池的所有位置都属于这个集合。
/// 位置在池中的唯一索引存储在代币属性映射中。
/// TOKEN_BURNABLE_BY_OWNER存储在每个位置的默认属性映射中，
/// 这样当位置流动性为零时，创建者可以销毁代币。
module eden_clmm::position_nft {
    use std::string::{Self, String};
    use std::bcs;
    use std::signer;
    use aptos_token::token;
    use eden_clmm::utils;
    use std::vector;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::object::Object;

   // 创建位置NFT集合
   // 参数：
   //     - creator: 创建者（池资源账户）
   //     - tick_spacing: 池的tick间距
   //     - description: 集合描述
   //     - uri: NFT集合URI
   //     - metadata_a: 代币A的元数据
   //     - metadata_b: 代币B的元数据
   // 返回：集合名称
    public fun create_collection(
        creator: &signer,
        tick_spacing: u64,
        description: String,
        uri: String,
        metadata_a: Object<Metadata>,
        metadata_b: Object<Metadata>
    ): String {
        let collection = collection_name(tick_spacing, metadata_a, metadata_b);
        let mutate_setting = vector::empty<bool>();
        mutate_setting.push_back(true); // 描述可变
        mutate_setting.push_back(true); // 最大供应量可变
        mutate_setting.push_back(true); // URI可变
        token::create_collection(
            creator,
            collection,
            description,
            uri,
            0, // 无限供应量
            mutate_setting
        );
        collection
    }

   // 铸造位置NFT
   // 参数：
   //     - user: NFT接收者
   //     - creator: 创建者
   //     - pool_index: 池索引
   //     - position_index: 位置索引
   //     - pool_uri: 池URI
   //     - collection: NFT集合
    public fun mint(
        user: &signer,
        creator: &signer,
        pool_index: u64,
        position_index: u64,
        pool_uri: String,
        collection: String
    ) {
        let name = position_name(pool_index, position_index);
        let mutate_setting = vector<bool>[false, false, false, false, true];
        token::create_token_script(
            creator,
            collection,
            name,
            string::utf8(b""), // 空描述
            1, // 总供应量为1
            1, // 最大供应量为1
            pool_uri,
            signer::address_of(creator),
            1000000, // 版税分母
            0, // 版税分子（无版税）
            mutate_setting,
            vector<String>[
                string::utf8(b"index"),
                string::utf8(b"TOKEN_BURNABLE_BY_CREATOR")
            ],
            vector<vector<u8>>[bcs::to_bytes<u64>(&position_index), bcs::to_bytes<bool>(
                &true
            )],
            vector<String>[string::utf8(b"u64"), string::utf8(b"bool")]
        );
        // 将代币转移给接收者
        token::direct_transfer_script(
            creator,
            user,
            signer::address_of(creator),
            collection,
            name,
            0, // 属性版本
            1 // 数量
        );
    }

   // 销毁位置NFT
   // 参数：
   //     - creator: NFT创建者
   //     - user: NFT所有者
   //     - collection_name: 集合名称
   //     - pool_index: 池索引
   //     - pos_index: 位置索引
    public fun burn(
        creator: &signer,
        user: address,
        collection_name: String,
        pool_index: u64,
        pos_index: u64
    ) {
        token::burn_by_creator(
            creator,
            user,
            collection_name,
            position_name(pool_index, pos_index),
            0,
            1
        );
    }

   // 生成位置NFT名称
   // 参数：
   //     - pool_index: 池索引
   //     - index: 位置索引
   // 返回：位置名称字符串
    public fun position_name(pool_index: u64, index: u64): String {
        let name = string::utf8(b"Eden LP | Pool");
        name.append(utils::str(pool_index));
        name.append_utf8(b"-");
        name.append(utils::str(index));
        name
    }

   // 生成位置代币集合唯一名称
   // 格式："Eden Position | tokenA-tokenB_tick(#)"
   // 参数：
   //     - tick_spacing: tick间距
   //     - metadata_a: 代币A的元数据
   //     - metadata_b: 代币B的元数据
   // 返回：集合名称字符串
    public fun collection_name(
        tick_spacing: u64,
        metadata_a: Object<Metadata>,
        metadata_b: Object<Metadata>
    ): String {
        let collect_name = string::utf8(b"Eden Position | ");
        collect_name.append(fungible_asset::symbol(metadata_a));
        collect_name.append_utf8(b"-");
        collect_name.append(fungible_asset::symbol(metadata_b));
        collect_name.append_utf8(b"_tick(");
        collect_name.append(utils::str(tick_spacing));
        collect_name.append_utf8(b")");
        collect_name
    }

   // 修改集合URI
   // 参数：
   //     - _creator: 创建者
   //     - _collection: 集合名称
   //     - _uri: 新URI
   // 注意：目前在主网不支持
    public fun mutate_collection_uri(
        _creator: &signer, _collection: String, _uri: String
    ) {
        // 目前在主网不支持
        // token::mutate_collection_uri(creator, collection, uri)
    }
}
