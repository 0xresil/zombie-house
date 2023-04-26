module zombie_house::zombie_house {
  
  use std::string::{Self, String};
  use std::vector;
  use std::option;
  // use std::type_name::{Self, TypeName};
  use sui::coin::{Self, Coin};
  use sui::balance::{Self, Balance};
  use sui::object::{Self, ID, UID};
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};
  use sui::ed25519;
  // use sui::sui::SUI;
  // use sui::clock::{Self, Clock};
  
  use sui::display;
  use sui::url::{Self, Url};
  use sui::event;

  use nft_protocol::collection;
  use nft_protocol::witness;
  use nft_protocol::display_info;
  use nft_protocol::mint_cap::MintCap;

  use zbs_coin::zbs_coin::ZBS_COIN;

  const EINVALID_OWNER: u64 = 1;
  const EESCROW_ALREADY_INITED: u64 = 2;
  const EINVALID_PARTIES: u64 = 3;
  const EWRONG_ZOMBIE_AMOUNT: u64 = 4;
  const EINSUFFICIENT_ZPT_AMOUNT: u64 = 5;
  const EINVALID_GAME_MASTER: u64 = 6;
  const EEXCEED_MAX_ZOMBIE_COUNT: u64 = 7;
  const EINVALID_CLAIM_NONCE: u64 = 8;
  const EINVALID_CLAIM_AMOUNT: u64 = 9;
  const EINVALID_SIGNATURE: u64 = 10;
  const EALREADY_GOT_AIRDROP: u64 = 11;
  const EINVLAID_AIRDROP_STATUS: u64 = 12;

  // zpt is 9 decimals
  const TOKEN_DECIMAL: u64 = 1000000000;
  const NFT_NAMES: vector<vector<u8>> = vector[
    b"Baby",
    b"Butcher",
    b"Clown",
    b"Police",
    b"Priate",
  ];
  const AIRDROP_AMOUNT: u64 = 1000 * 1000000000;

  /// One time witness is only instantiated in the init method
  struct ZOMBIE_HOUSE has drop {}

  /// Used for authorization of other protected actions.
  ///
  /// `Witness` must not be freely exposed to any contract.
  struct Witness has drop {}

  struct ZombieNFT has key, store {
    id: UID,
    name: String,
    description: String,
    url: Url,
    token_id: u64
  }

  struct ZombieInfo has copy, drop, store {
    zombie_owner: address,
    zombie_id: u32,
    level: u8, //1,2,3,4,5
    type: u8,
  }

  struct GameInfo has key {
    id: UID,
    owner: address,
    game_master: address,
    domain: String,
    sig_verify_pk: vector<u8>,
    zombies: vector<ZombieInfo>,
    zpt_pot: Balance<ZBS_COIN>,
    // zpt_type: TypeName,
    price_token_per_zombie: u64,
    max_zombie_per_player: u64,
    mint_cap: MintCap<ZombieNFT>,
    current_nft_index: u64,
    earned_zpt_amt: u64,
    claim_nonce: u64,

    // aidrop
    airdrop_amount: u64,
    airdrop_status: u8,
    claimed_users: vector<address>
  }

  // events
  struct NFTMinted has copy, drop {
    object_id: ID,
    creator: address,
    name: String
  }

  struct PayerBuyZombies has copy, drop {
    player: address,
    zombie_ids: vector<u32>,
    zombie_types: vector<u8>
  }

  struct PlayerClaimedEarnedZPT has copy, drop {
    player: address,
    amount: u64,
    nonce: u64
  }
  
  fun init(otw: ZOMBIE_HOUSE, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    
    // Init Collection & MintCap with unlimited supply
    let (collection, mint_cap) = collection::create_with_mint_cap<ZOMBIE_HOUSE, ZombieNFT>(
        &otw, option::none(), ctx
    );

    let publisher = sui::package::claim(otw, ctx);

    // Init Display
    let display = display::new<ZombieNFT>(&publisher, ctx);
    display::add(&mut display, string::utf8(b"name"), string::utf8(b"{name}"));
    display::add(&mut display, string::utf8(b"description"), string::utf8(b"{description}"));
    display::add(&mut display, string::utf8(b"image_url"), string::utf8(b"https://{url}"));
    display::update_version(&mut display);
    transfer::public_transfer(display, sender);

    // Get the Delegated Witness
    let dw = witness::from_witness(Witness {});
    collection::add_domain(
        dw,
        &mut collection,
        display_info::new(
            string::utf8(b"ZombiePets"),
            string::utf8(b"ZombiePets collection on Sui"),
        )
    );

    // send publisher object to deployer
    transfer::public_transfer(publisher, sender);

    // todo: transfer::share_object -> gameInfo
    transfer::share_object(GameInfo {
      id: object::new(ctx),
      owner: sender,
      game_master: sender,
      sig_verify_pk: vector::empty<u8>(),
      domain: string::utf8(b"gateway.pinata.cloud/ipfs/QmR7vqrR3eHuW2LmJq7P5i915M6pvHqoJmcQrdunDEYL4j/"),
      zombies: vector::empty<ZombieInfo>(),
      zpt_pot: balance::zero<ZBS_COIN>(),
      // zpt_type: TypeName,
      price_token_per_zombie: 1000*TOKEN_DECIMAL,
      max_zombie_per_player: 20,
      mint_cap,
      current_nft_index: 0,
      earned_zpt_amt: 0,
      claim_nonce: 0,

      airdrop_amount: AIRDROP_AMOUNT,
      airdrop_status: 1,
      claimed_users: vector::empty<address>()
    });

    transfer::public_share_object(collection);
  }

  public entry fun claim_earned_zpt(
    game_info: &mut GameInfo,
    claim_amount: u64,
    sig: vector<u8>,
    ctx: &mut TxContext
  ) {
    assert!(verify_claim_sig(claim_amount, game_info.claim_nonce, game_info.sig_verify_pk, sig), EINVALID_SIGNATURE);

    let sender = tx_context::sender(ctx);
    let pot_amount = balance::value(&game_info.zpt_pot);
    assert!(claim_amount < pot_amount, EINVALID_CLAIM_AMOUNT);

    let zpt_to_claim: Coin<ZBS_COIN> = coin::take(&mut game_info.zpt_pot, claim_amount, ctx);
    transfer::public_transfer(zpt_to_claim, sender);

    game_info.claim_nonce = game_info.claim_nonce + 1;

    event::emit(PlayerClaimedEarnedZPT {
        player: sender,
        nonce: game_info.claim_nonce,
        amount: claim_amount
    });
  }
  /// buy zombie with specific amount of zpt token
  public entry fun buy_zombie(
    game_info: &mut GameInfo,
    paid: Coin<ZBS_COIN>, 
    nft_count: u64,
    types: vector<u8>,
    types_sig: vector<u8>,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);

    assert!(nft_count != 0, EWRONG_ZOMBIE_AMOUNT);
    let zpt_required = nft_count * game_info.price_token_per_zombie;
    assert!(coin::value(&paid) > zpt_required, EINSUFFICIENT_ZPT_AMOUNT);
    assert!(verify_types_sig(types, game_info.current_nft_index, game_info.sig_verify_pk, types_sig) == true, EINVALID_SIGNATURE);

    // check nft count per user
    assert!(get_zombie_amount(&game_info.zombies, sender) < game_info.max_zombie_per_player, EEXCEED_MAX_ZOMBIE_COUNT);

    let paid_amount = coin::value(&paid);
    let paid_balance = coin::into_balance(paid);
    let zpt_to_return: Coin<ZBS_COIN> = coin::take(&mut paid_balance, paid_amount - zpt_required, ctx);
    // transfer extra coin to sender
    transfer::public_transfer(zpt_to_return, sender);
    balance::join(&mut game_info.zpt_pot, paid_balance);

    game_info.earned_zpt_amt = game_info.earned_zpt_amt + zpt_required;

    let created_zombies: vector<u32> = vector::empty();
    let i = 0;
    while (i < nft_count) {

      let nft_type = *vector::borrow(&types, i);

      game_info.current_nft_index = game_info.current_nft_index + 1;
      vector::push_back(
        &mut game_info.zombies, 
        ZombieInfo {
          zombie_owner: sender,
          zombie_id: (game_info.current_nft_index as u32),
          level: 1,
          type: nft_type
      });

      // mint nft
      mint_nft(
        get_nft_name(nft_type), 
        string::utf8(b"This is a Zombie NFT who makes ZPT coins."), 
        get_nft_uri(game_info.domain, nft_type), 
        game_info.current_nft_index,
        &game_info.mint_cap,
        ctx
      );
      vector::push_back(&mut created_zombies, (game_info.current_nft_index as u32));
      i = i + 1;
    };

    event::emit(PayerBuyZombies {
        player: sender,
        zombie_ids: created_zombies,
        zombie_types: types
    });
  }

  /// only master can mint zombies
  public entry fun master_mint_zombie(
    game_info: &mut GameInfo,
    zombie_count: u64, 
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // check master cap
    assert!(sender == game_info.game_master, EINVALID_GAME_MASTER);
    let i = 0;
    while (i < zombie_count) {
      game_info.current_nft_index = game_info.current_nft_index + 1;
      // mint nft
      let nft_type = 4;
      mint_nft(
        get_nft_name(nft_type),
        string::utf8(b"This is a test Zombie NFT"), 
        get_nft_uri(game_info.domain, nft_type), 
        game_info.current_nft_index,
        &game_info.mint_cap,
        ctx
      );
      i = i + 1;
    }
  }

  /// owner withdraw zpt from the contract
  public entry fun withdraw_zpt (
    game_info: &mut GameInfo,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender == game_info.owner, EINVALID_OWNER);

    let pot_amount = balance::value(&game_info.zpt_pot);
    let zpt_to_withdraw: Coin<ZBS_COIN> = coin::take(&mut game_info.zpt_pot, pot_amount, ctx);
    transfer::public_transfer(zpt_to_withdraw, sender);
  }

  /// owner deposit zpt to the contract for airdrop
  public entry fun deposit_zpt (
    game_info: &mut GameInfo,
    deposit_zpt: Coin<ZBS_COIN>, 
    amount: u64,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender == game_info.owner, EINVALID_OWNER);

    let paid_amount = coin::value(&deposit_zpt);
    let paid_balance = coin::into_balance(deposit_zpt);
    let zpt_to_return: Coin<ZBS_COIN> = coin::take(&mut paid_balance, paid_amount - amount, ctx);
    // transfer extra coin to sender
    transfer::public_transfer(zpt_to_return, sender);
    balance::join(&mut game_info.zpt_pot, paid_balance);
  }

  /// airdrop
  public entry fun get_airdrop (
    game_info: &mut GameInfo,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);

    assert!(game_info.airdrop_status == 1, EINVLAID_AIRDROP_STATUS);
    assert!(!vector::contains(&game_info.claimed_users, &sender), EALREADY_GOT_AIRDROP);

    let pot_amount = balance::value(&game_info.zpt_pot);
    assert!(game_info.airdrop_amount <= pot_amount, EINSUFFICIENT_ZPT_AMOUNT);

    let zpt_to_withdraw: Coin<ZBS_COIN> = coin::take(&mut game_info.zpt_pot, game_info.airdrop_amount, ctx);
    transfer::public_transfer(zpt_to_withdraw, sender);

    vector::push_back(&mut game_info.claimed_users, sender);
  }

  /// update base_uri of nft token_uri
  public entry fun set_verify_pk (
    game_info: &mut GameInfo,
    verify_pk_str: String,
    ctx: &mut TxContext,
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender == game_info.owner, EINVALID_OWNER);
    game_info.sig_verify_pk = sui::hex::decode(*string::bytes(&verify_pk_str));
  }

  /// update base_uri of nft token_uri
  public entry fun update_domain (
    game_info: &mut GameInfo,
    domain: String,
    ctx: &mut TxContext,
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender == game_info.owner, EINVALID_OWNER);
    game_info.domain = domain;
  }

  /// update zpt amount to mint a zombie
  public entry fun update_zpt_per_zombie (
    game_info: &mut GameInfo,
    zpt_amount: u64,
    ctx: &mut TxContext,
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender == game_info.owner, EINVALID_OWNER);
    game_info.price_token_per_zombie = zpt_amount;
  }

  /// update max limit of mintable zombie count per player
  public entry fun update_max_zombies_per_player (
    game_info: &mut GameInfo,
    max_amount: u64,
    ctx: &mut TxContext,
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender == game_info.owner, EINVALID_OWNER);
    game_info.max_zombie_per_player = max_amount;
  }

  /// update master address
  public entry fun update_master_address (
    game_info: &mut GameInfo,
    master_address: address,
    ctx: &mut TxContext,
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender == game_info.owner, EINVALID_OWNER);
    game_info.game_master = master_address;
  }

  /// update airdrop status
  public entry fun update_airdrop_status (
    game_info: &mut GameInfo,
    new_status: u8,
    ctx: &mut TxContext,
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender == game_info.owner, EINVALID_OWNER);
    game_info.airdrop_status = new_status;
  }

  /// update airdrop status
  public entry fun update_airdrop_amount (
    game_info: &mut GameInfo,
    new_amount: u64,
    ctx: &mut TxContext,
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender == game_info.owner, EINVALID_OWNER);
    game_info.airdrop_amount = new_amount;
  }
  
  /// Create a new zombie nft
  fun mint_nft(
      name: String,
      description: String,
      url: String,
      token_id: u64,
      _mint_cap: &MintCap<ZombieNFT>,
      ctx: &mut TxContext
  ) {
      let sender = tx_context::sender(ctx);
      let nft = ZombieNFT {
          id: object::new(ctx),
          name,
          description,
          url: url::new_unsafe(string::to_ascii(url)),
          token_id
      };

      event::emit(NFTMinted {
          object_id: object::id(&nft),
          creator: sender,
          name: nft.name,
      });

      transfer::transfer(nft, sender);
  }

  fun get_zombie_amount(zombies: &vector<ZombieInfo>, owner: address): u64 {
    let index = 0;
    let zombie_count: u64 = 0;
    while (index < vector::length(zombies)) {
      let zombie_info = vector::borrow(zombies, index);
      if (zombie_info.zombie_owner == owner) {
        zombie_count = zombie_count + 1;
      };
      index = index + 1;
    };
    zombie_count
  }

  fun get_nft_uri(domain: String, nft_type: u8): String {
    let id_str = domain;
    let type_str = string::utf8(b"0");
    if (nft_type == 1) type_str = string::utf8(b"1");
    if (nft_type == 2) type_str = string::utf8(b"2");
    if (nft_type == 3) type_str = string::utf8(b"3");
    if (nft_type == 4) type_str = string::utf8(b"4");

    string::append(&mut id_str, type_str);
    id_str
  }

  fun get_nft_name(nft_type: u8): String {
    if (nft_type > 4) nft_type = 4;
    let name_str = string::utf8(*vector::borrow(&mut NFT_NAMES, (nft_type as u64)));
    string::append(&mut name_str, string::utf8(b" Zombie NFT"));
    name_str
  }

  fun verify_claim_sig(claim_amount: u64, claim_nonce: u64, verify_pk: vector<u8>, signature: vector<u8>): bool {
    
    let amount_bytes = std::bcs::to_bytes(&(claim_amount as u64));
    let nonce_bytes = std::bcs::to_bytes(&(claim_nonce as u64));
    vector::append(&mut amount_bytes, nonce_bytes);
    let verify = ed25519::ed25519_verify(
      &signature, 
      &verify_pk, 
      &amount_bytes
    );
    verify
  }
  
  fun verify_types_sig(types: vector<u8>, cur_nft_index: u64, verify_pk: vector<u8>, signature: vector<u8>): bool {
    let sign_data = types;
    let index_bytes = std::bcs::to_bytes(&cur_nft_index);
    vector::append(&mut sign_data, index_bytes);

    std::debug::print<String>(&string::utf8(b"verify_types_sig"));
    std::debug::print<vector<u8>>(&sign_data);

    let verify = ed25519::ed25519_verify(
      &signature, 
      &verify_pk, 
      &sign_data
    );
    verify
  }

  // === Integration test ===

  #[test_only]
  use sui::test_scenario::{Self, ctx};
  #[test_only]
  use nft_protocol::collection::Collection;

  #[test_only]
  const USER: address = @0xA1C04;

  #[test_only]
  fun number_to_string(number: u64): String {
    let num_str = std::ascii::string(b"");
    let ascii_vec = vector::empty<u8>();
    while (number > 0) {
      let char_ascii = number % 10 + 48;
      vector::push_back(&mut ascii_vec, (char_ascii as u8));
      number = number / 10u64;
    };

    // std::debug::print<vector<u8>>(&ascii_vec);

    let i = 0;
    let len = vector::length(&ascii_vec);
    while (i < len) {
      let char = vector::pop_back(&mut ascii_vec);
      std::ascii::push_char(&mut num_str, std::ascii::char(char));
      i = i + 1;
    };

    string::from_ascii(num_str)
  }

  #[test]
  fun it_inits_collection() {
      let scenario = test_scenario::begin(USER);

      init(ZOMBIE_HOUSE {}, ctx(&mut scenario));
      test_scenario::next_tx(&mut scenario, USER);

      assert!(test_scenario::has_most_recent_shared<Collection<ZombieNFT>>(), 0);

      let game_info = test_scenario::take_shared<GameInfo>(
          &scenario
      );

      mint_nft(
          string::utf8(b"Simple NFT"),
          string::utf8(b"A simple NFT on Sui"),
          string::utf8(b"test.xyz"),
          0u64,
          &game_info.mint_cap,
          ctx(&mut scenario)
      );

      test_scenario::return_shared<GameInfo>(game_info);
      test_scenario::next_tx(&mut scenario, USER);

      assert!(test_scenario::has_most_recent_for_address<ZombieNFT>(USER), 0);
      // std::debug::print<string::String>(&number_to_string(100));
      // assert!(number_to_string(100) == string::utf8(b"100"), 1);

      let cur_nft_index = 101u64;
      let sign_data: vector<u8> = vector[2, 0, 3, 4, 3, 4, 2, 2, 1, 2];
      std::debug::print<vector<u8>>(&sign_data);
      let index_bytes = std::bcs::to_bytes(&(cur_nft_index as u64));
      vector::append(&mut sign_data, index_bytes);
      std::debug::print<vector<u8>>(&sign_data);

      let signature: vector<u8> = x"b11280dc26ad7fd9165f4d4aef78b5946fe4714d481d6a4032c6fd510bdc89d4345c0fc9ead0dbe899db6fc8b0d826a11bb813847538286add0affe77a384101";
      let verify_pk: vector<u8> = x"66f7b2553f81cc9015b4ee3ffd3b3f607b2af5398f3889319e669f9db28429f6";
      
      let verify = ed25519::ed25519_verify(&signature, &verify_pk, &sign_data);
      std::debug::print<bool>(&verify);

      let verify1 = ed25519::ed25519_verify(
        &x"b11280dc26ad7fd9165f4d4aef78b5946fe4714d481d6a4032c6fd510bdc89d4345c0fc9ead0dbe899db6fc8b0d826a11bb813847538286add0affe77a384101", 
        &x"66f7b2553f81cc9015b4ee3ffd3b3f607b2af5398f3889319e669f9db28429f6", 
        &sign_data
      );
      std::debug::print<bool>(&verify1);

      std::debug::print<bool>(&verify_types_sig(
        vector[2, 0, 3, 4, 3, 4, 2, 2, 1, 2],
        cur_nft_index,
        x"66f7b2553f81cc9015b4ee3ffd3b3f607b2af5398f3889319e669f9db28429f6",
        x"b11280dc26ad7fd9165f4d4aef78b5946fe4714d481d6a4032c6fd510bdc89d4345c0fc9ead0dbe899db6fc8b0d826a11bb813847538286add0affe77a384101",
      ));

      std::debug::print<bool>(&verify_claim_sig(
        20000,
        101,
        x"66f7b2553f81cc9015b4ee3ffd3b3f607b2af5398f3889319e669f9db28429f6",
        x"1524c0d09c4c973580401d11b5f5a74daa9b42f308a7afb707eaf18b62ad483e0d9dc9cb389b339e8ad771dcfe8d63a72a3517db77bd154f9521624253e8600f",
      ));


      std::debug::print<vector<u8>>(&x"66f7b2553f81cc9015b4ee3ffd3b3f607b2af5398f3889319e669f9db28429f6");
      std::debug::print<vector<u8>>(&sui::hex::decode(b"66f7b2553f81cc9015b4ee3ffd3b3f607b2af5398f3889319e669f9db28429f6"));
      
      std::debug::print<String>(&get_nft_name(0));

      let str = string::utf8(b"66f7b2553f81cc9015b4ee3ffd3b3f607b2af5398f3889319e669f9db28429f6");
      std::debug::print<String>(&str);
      std::debug::print<vector<u8>>(&sui::hex::decode(*string::bytes(&str)));

      std::debug::print<bool>(&verify_types_sig(
        vector[1],
        0,
        x"66f7b2553f81cc9015b4ee3ffd3b3f607b2af5398f3889319e669f9db28429f6",
        x"4e7819d7cae068297c2ebc8ca1fc2a3191d26aa6cd2caff9cefd37cb680054f3b59c9893260a419a341c45fad56e596e7f59af76545dd84bdaf20e767093780f",
      ));

      std::debug::print<bool>(&verify_claim_sig(
        1000,
        0,
        x"66f7b2553f81cc9015b4ee3ffd3b3f607b2af5398f3889319e669f9db28429f6",
        x"eb99203e09809d539833282754b18b712082e1477367f0af9d6dd18900bbb75611d3fc8dea0b8815f45db398f7ac3e256d63e6f193b11692b0871f1c3e58e803",
      ));

      test_scenario::end(scenario);
  }
}