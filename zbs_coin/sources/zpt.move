module zbs_coin::zbs_coin {
  
  use std::option;
  use sui::coin::{Self};
  //use sui::object::{Self, ID, UID};
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};
  use sui::url::{Self};

  struct ZBS_COIN has drop {}

  fun init(otw: ZBS_COIN, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    let (treasury_cap, metadata) = coin::create_currency<ZBS_COIN>(
        otw, 
        9, 
        b"ZBS", 
        b"Zombie Sui Coin", 
        b"Reward Token from Zombie Sui NFTs", 
        option::some(url::new_unsafe_from_bytes(
          b"https://s2.coinmarketcap.com/static/img/coins/64x64/12192.png"
        )), 
        ctx
    );
    transfer::public_freeze_object(metadata);

    // mint coins to owner
    let minted_coin = coin::mint(&mut treasury_cap, 1_000_000_000_000_000_000, ctx);
    transfer::public_transfer(minted_coin, sender);

    // transfer treasury_cap
    transfer::public_transfer(treasury_cap, sender);
  }

  #[test_only]
  use sui::test_scenario::{Self, ctx};

  #[test_only]
  const USER: address = @0xA1C04;

  #[test_only]
  use sui::coin::{Coin};

  #[test]
  fun it_inits_module() {
      let scenario = test_scenario::begin(USER);

      init(ZBS_COIN {}, ctx(&mut scenario));
      test_scenario::next_tx(&mut scenario, USER);

      let coin1 = test_scenario::take_from_sender<Coin<ZBS_COIN>>(&mut scenario);
      assert!(coin::value(&coin1) == 1_000_000_000_000_000_000, 111);
      test_scenario::return_to_address(USER, coin1);
      // assert!(!test_scenario::has_most_recent_for_sender<TreasuryCap<ZBS_COIN>>(&mut scenario), 0);

      test_scenario::next_tx(&mut scenario, USER);
      test_scenario::end(scenario);
  }
}