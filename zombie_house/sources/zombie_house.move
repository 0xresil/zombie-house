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
  // use sui::sui::SUI;
  // use sui::clock::{Self, Clock};
  
  use sui::display;
  use sui::url::{Self, Url};
  use sui::event;

  use nft_protocol::collection;
  use nft_protocol::witness;
  use nft_protocol::display_info;
  use nft_protocol::mint_cap::MintCap;

  use zpt_coin::zpt_coin::ZPT_COIN;

  const EINVALID_OWNER: u64 = 1;
  const EESCROW_ALREADY_INITED: u64 = 2;
  const EINVALID_PARTIES: u64 = 3;
  const EWRONG_ZOMBIE_AMOUNT: u64 = 4;
  const EINSUFFICIENT_ZPT_AMOUNT: u64 = 5;
  const EINVALID_GAME_MASTER: u64 = 6;
  const EEXCEED_MAX_ZOMBIE_COUNT: u64 = 7;

  // zpt is 9 decimals
  const TOKEN_DECIMAL: u64 = 1000000000;

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
    url: Url
  }

  struct NFTMinted has copy, drop {
    object_id: ID,
    creator: address,
    name: String
  }

  struct ZombieInfo has copy, drop, store {
    zombie_owner: address,
    zombie_id: u32,
    level: u8 //1,2,3,4,5
  }

  struct GameInfo has key {
    id: UID,
    owner: address,
    game_master: address,
    domain: String,
    zombies: vector<ZombieInfo>,
    zpt_pot: Balance<ZPT_COIN>,
    // zpt_type: TypeName,
    price_token_per_zombie: u64,
    max_zombie_per_player: u64,
    mint_cap: MintCap<ZombieNFT>,
    current_nft_index: u64,
    earned_zpt_amt: u64
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
      domain: string::utf8(b"https://app.zombiepets.io/detail/"),
      zombies: vector::empty<ZombieInfo>(),
      zpt_pot: balance::zero<ZPT_COIN>(),
      // zpt_type: TypeName,
      price_token_per_zombie: 1000*TOKEN_DECIMAL,
      max_zombie_per_player: 20,
      mint_cap,
      current_nft_index: 0,
      earned_zpt_amt: 0
    });

    transfer::public_share_object(collection);
  }

  /// Create a new zombie nft
  fun mint_nft(
      name: String,
      description: String,
      url: String,
      _mint_cap: &MintCap<ZombieNFT>,
      ctx: &mut TxContext
  ) {
      let sender = tx_context::sender(ctx);
      let nft = ZombieNFT {
          id: object::new(ctx),
          name,
          description,
          url: url::new_unsafe(string::to_ascii(url))
      };

      event::emit(NFTMinted {
          object_id: object::id(&nft),
          creator: sender,
          name: nft.name,
      });

      transfer::public_transfer(nft, sender);
  }

  fun get_zombie_amount(zombies: &vector<ZombieInfo>, owner: address): u64 {
    let index = 0;
    let zombie_count: u64 = 0;
    while (index < vector::length(zombies)) {
      let zombie_info = vector::borrow(zombies, index);
      if (zombie_info.zombie_owner == owner) {
        zombie_count = zombie_count + 1;
      }
    };
    zombie_count
  }

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

  fun get_nft_uri(domain: String, nft_id: u64): String {
    let id_str = domain;
    string::append(&mut id_str, number_to_string(nft_id));
    id_str
  }

  public entry fun buy_zombie(
    game_info: &mut GameInfo,
    paid: Coin<ZPT_COIN>, 
    nft_count: u64, 
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);

    assert!(nft_count != 0, EWRONG_ZOMBIE_AMOUNT);
    let zpt_required = nft_count * game_info.price_token_per_zombie;
    assert!(coin::value(&paid) > zpt_required, EINSUFFICIENT_ZPT_AMOUNT);

    // check nft count per user
    assert!(get_zombie_amount(&game_info.zombies, sender) < game_info.max_zombie_per_player, EEXCEED_MAX_ZOMBIE_COUNT);

    let paid_amount = coin::value(&paid);
    let paid_balance = coin::into_balance(paid);
    let zpt_to_return: Coin<ZPT_COIN> = coin::take(&mut paid_balance, paid_amount - zpt_required, ctx);
    // transfer extra coin to sender
    transfer::public_transfer(zpt_to_return, sender);
    // let sui_balance = coin::into_balance(paid);
    balance::join(&mut game_info.zpt_pot, paid_balance);

    game_info.earned_zpt_amt = game_info.earned_zpt_amt + zpt_required;

    let i = 0;
    while (i < nft_count) {
      game_info.current_nft_index = game_info.current_nft_index + 1;
      vector::push_back(
        &mut game_info.zombies, 
        ZombieInfo {
          zombie_owner: sender,
          zombie_id: (game_info.current_nft_index as u32),
          level: 1,
      });

      // mint nft
      mint_nft(
        string::utf8(b"Zombie NFT"), 
        string::utf8(b"This is a test Zombie NFT"), 
        get_nft_uri(game_info.domain, game_info.current_nft_index), 
        &game_info.mint_cap,
        ctx
      );
      i = i + 1;
    }
  }

  public entry fun master_mint_zombie(
    game_info: &mut GameInfo,
    zombie_count: u64, 
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // check master cap
    assert!(sender != game_info.game_master, EINVALID_GAME_MASTER);
    let i = 0;
    while (i < zombie_count) {
      game_info.current_nft_index = game_info.current_nft_index + 1;
      // mint nft
      // todo: url modify
      mint_nft(
        string::utf8(b"Zombie NFT"), 
        string::utf8(b"This is a test Zombie NFT"), 
        get_nft_uri(game_info.domain, game_info.current_nft_index), 
        &game_info.mint_cap,
        ctx
      );
      i = i + 1;
    }
  }

  public entry fun withdraw_zpt (
    game_info: &mut GameInfo,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender != game_info.owner, EINVALID_OWNER);

    let pot_amount = balance::value(&game_info.zpt_pot);
    let zpt_to_withdraw: Coin<ZPT_COIN> = coin::take(&mut game_info.zpt_pot, pot_amount, ctx);
    transfer::public_transfer(zpt_to_withdraw, sender);
  }

  public entry fun deposit_zpt (
    game_info: &mut GameInfo,
    deposit_zpt: Coin<ZPT_COIN>, 
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender != game_info.owner, EINVALID_OWNER);

    let sui_balance = coin::into_balance(deposit_zpt);
    balance::join(&mut game_info.zpt_pot, sui_balance);
  }

  public entry fun update_domain (
    game_info: &mut GameInfo,
    domain: String,
    ctx: &mut TxContext,
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender != game_info.owner, EINVALID_OWNER);
    game_info.domain = domain;
  }

  public entry fun update_zpt_per_zombie (
    game_info: &mut GameInfo,
    zpt_amount: u64,
    ctx: &mut TxContext,
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender != game_info.owner, EINVALID_OWNER);
    game_info.price_token_per_zombie = zpt_amount;
  }

  public entry fun update_max_zombies_per_player (
    game_info: &mut GameInfo,
    max_amount: u64,
    ctx: &mut TxContext,
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender != game_info.owner, EINVALID_OWNER);
    game_info.max_zombie_per_player = max_amount;
  }

  public entry fun update_master_address (
    game_info: &mut GameInfo,
    master_address: address,
    ctx: &mut TxContext,
  ) {
    let sender = tx_context::sender(ctx);
    // check ownership
    assert!(sender != game_info.owner, EINVALID_OWNER);
    game_info.game_master = master_address;
  }

  // === Integration test ===

  #[test_only]
  use sui::test_scenario::{Self, ctx};
  #[test_only]
  use nft_protocol::collection::Collection;

  #[test_only]
  const USER: address = @0xA1C04;

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
          &game_info.mint_cap,
          ctx(&mut scenario)
      );

      test_scenario::return_shared<GameInfo>(game_info);
      test_scenario::next_tx(&mut scenario, USER);

      assert!(test_scenario::has_most_recent_for_address<ZombieNFT>(USER), 0);
      std::debug::print<string::String>(&number_to_string(100));
      assert!(number_to_string(100) == string::utf8(b"100"), 1);
      test_scenario::end(scenario);
  }
}