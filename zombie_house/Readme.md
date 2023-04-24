### 1. set verify pk in smart contract
### 2. update originalPackageId in public/js/suiweb3.js
        update packageId in public/js/account.js
        update packageId in public/js/airdrop.js
        update zptCoinType in public/js/account.js
### 3. deposit to pot


# How to upgrade
- modify Move.toml, published-at = "0xe1956a88b8810a248a5fb8b3063e57d97fe17b6318996620908d8512da3bcb93"
- upgrade
sui client upgrade --upgrade-capability 0x2d4759a0fe1263fd8d92bc73a5d56cbd8481d712aab1862059c62b6168c6dbb7 --gas-budget 1000000
- modify packageId in account.js
  update packageId in public/js/airdrop.js

# modify token link in airdrop.ejs
https://explorer.sui.io/object/0x56c77a6802092355c906ba967f2f557189b1bf6ccf0f5a15e53fe0b13d83da12?network=https%3A%2F%2Ffullnode.devnet.sui.io%3A443

https://fullnode.devnet.sui.io:443
```sh
sui client envs
devnet => https://fullnode.devnet.sui.io:443 (active)
```
```sh
sui client addresses
sui client gas

sui move build
sui client publish --gas 0x49e8321ff1f132544c0e4218876bf80742bd06b8f51a04976474808e6b5d6440 --gas-budget 300000000
```