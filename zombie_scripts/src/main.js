const { 
  JsonRpcProvider, 
  Connection, 
  RawSigner, 
  TransactionBlock, 
  Ed25519Keypair, 
  Secp256k1Keypair,
  verifyMessage,
  fromSerializedSignature,
  IntentScope
} = require('@mysten/sui.js');
const BigNumber = require('bignumber.js');
const { fromHEX, toHEX } = require('@mysten/bcs');
const { secp256k1 } = require('@noble/curves/secp256k1');

const connection = new Connection({
  fullnode: 'https://fullnode.devnet.sui.io:443',
  faucet: 'https://faucet.devnet.sui.io/gas',
});

// const provider = new JsonRpcProvider(devnetConnection);
const provider = new JsonRpcProvider(connection);

const userAddress = "0x51657bf952923f065e2a4ae32bfe971a8c4f40ce4fed8590db4d024420a9e60a";
const zptCoinType = "0x56c77a6802092355c906ba967f2f557189b1bf6ccf0f5a15e53fe0b13d83da12::zpt_coin::ZPT_COIN";
const packageId = "0xe1956a88b8810a248a5fb8b3063e57d97fe17b6318996620908d8512da3bcb93";
// const deployTxHash = "B41moK2xazCDtsodqB42dKihE3H9vfvgn4gfDS3B7Bxn";
const gameInfoType = `${packageId}::zombie_house::GameInfo`;
const displayCreatedEvent = `0x2::display::DisplayCreated<${packageId}::zombie_house::ZombieNFT>`;
const claimZptEvent = `${packageId}::zombie_house::PlayerClaimedEarnedZPT`;

const get_coin_amount = async (
  userAddress,
  coinType = null,
  coinDecimals = 9,
) => {
  let balanceData = await provider.getBalance({
    owner: userAddress,
    coinType
  });
  let real_value = new BigNumber(balanceData.totalBalance).dividedBy(Math.pow(10, coinDecimals)).toString();
  console.log(real_value);
}
const registerClaimEvent = async () => {
  console.log("registerClaimEvent");
  await provider.subscribeEvent({
    filter: {
      MoveEventType: claimZptEvent
    }, 
    onMessage: (event) => {
      console.log("event =", event);
    }
  })
}

const registerAllEvents = async () => {
  console.log("registerAllEvents");
  await provider.subscribeEvent({
    filter: {
      MoveModule: {
        module: "zombie_house",
        package: packageId,
      }
    }, 
    onMessage: (event) => {
      console.log("allEvent =", event);
    }
  })
}

const getGameInfoAddress = async () => {
  let events = await provider.queryEvents({
    query: {
      MoveEventType: displayCreatedEvent,
    }
  });
  let publishTx = events.nextCursor.txDigest;

  let txBlock = await provider.getTransactionBlock({
    digest: publishTx,
    options: {
      showEffects: true,
      showObjectChanges: true,
      showEvents: true
    }
  });
  let changedObjects = txBlock.objectChanges;
  if (!changedObjects) return null;
  for (let object of changedObjects) {
    if (object.objectType === gameInfoType && object.type === "created") {
      return object.objectId;
    }
  }
  return null;
}

const getGameInfoFromContract = async (
  gameInfoId
) => {
  let gameInfoObj = await provider.getObject({ id: gameInfoId, options: { showContent: true } });
  return gameInfoObj.data.content.fields;
}

const getAllZombiesFromContract = async (
  gameInfoId
) => {
  let gameInfo = await getGameInfoFromContract(gameInfoId);
  let zombies = gameInfo.zombies;
  console.log('zombies =', zombies);
  return zombies;
}

const getZombieAmountFromContract = async (
  gameInfoId,
  ownerAddress
) => {
  let zombies = await getAllZombiesFromContract(gameInfoId);
  let zombieCount = 0;
  for (let zombie of zombies) {
    if (zombie.fields.zombie_owner === ownerAddress) {
      zombieCount ++;
    }
  }
  console.log('count =', zombieCount);
  return zombieCount;
}

async function validateTransaction(signer, tx) {
  const localDigest = await signer.getTransactionBlockDigest(tx);
  const result = await signer.signAndExecuteTransactionBlock({
    transactionBlock: tx,
    options: {
      showEffects: true,
    },
  });
  console.log('tx result =', result);
  // expect(localDigest).toEqual(getTransactionDigest(result));
  // expect(getExecutionStatusType(result)).toEqual('success');
}

const mergeCoins = async (
  userAddress,
  coinType
) => {
  let coins = await provider.getCoins({
    owner: userAddress,
    coinType
  });
}

const buyZombieWithToken = async (
  gameInfoId,
  zombieAmount
) => {
  let privKey = "0x441c0f64eaffbd00a52a8d122caa717378c940598790d8930eb713ef23e77275";
  let keypair = Ed25519Keypair.fromSecretKey(fromHEX(privKey));
  let suiAddress = keypair.getPublicKey().toSuiAddress();
  
  let tx = new TransactionBlock();
  let coins = await provider.getCoins({
    owner: suiAddress,
    coinType: zptCoinType
  });
  let coinIds = coins.data.map((coin) => coin.coinObjectId);
  if (coinIds.length > 1) {
    tx.mergeCoins(tx.object(coinIds[0]), coinIds.slice(1).map((id) => tx.object(id)));
  }

  let zombieTypes = new Array(zombieAmount).fill(0).map(v => Math.floor(Math.random() * 5));

  // const vec = tx.makeMoveVec({ objects: [tx.pure("1")] });
  
  tx.moveCall({
    target: `${packageId}::zombie_house::buy_zombie`,
    arguments: [
      tx.object(gameInfoId),
      tx.object(coinIds[0]),
      tx.pure(zombieAmount),
      tx.pure(zombieTypes.map(String)),
      tx.pure(zombieTypes.map(String))
    ],
  });

  await validateTransaction(new RawSigner(keypair, provider), tx);
}

const fetchEvent = async () => {
  let events = await provider.queryEvents({
    query: {
      Transaction: "HYm37U3MRMGy6SsRHKb22poV9Eve83tFVrvBVwvnLhfJ"
    }
  });
  console.log('events =', events);
  console.log('events =', events.data[0].parsedJson);
}

function numToUint8Array(num) {
  let arr = new Uint8Array(8);

  for (let i = 0; i < 8; i++) {
    arr[i] = num % 256;
    num = Math.floor(num / 256);
  }

  return arr;
}

const signTypesArray_ = async (nftCount) => {
  let privKey = "0x441c0f64eaffbd00a52a8d122caa717378c940598790d8930eb713ef23e77275";
  let keypair = Ed25519Keypair.fromSecretKey(fromHEX(privKey));
  const signer = new RawSigner(keypair, provider);
  // let types = new Uint8Array(nftCount + 8).fill(0).map(v => Math.floor(Math.random() * 5));
  let types = new Uint8Array([2, 0, 3, 4, 3, 4, 2, 2, 1, 2,   0, 0, 0, 0, 0, 0, 0, 0]);
  let oldTypes = types;
  types.set(numToUint8Array(101), nftCount);
  console.log(types);
  console.log("pubkey =", toHEX(keypair.getPublicKey().toBytes()));
  let signData = fromHEX("315f5bdb76d078c43b8ac0064e4a0164612b1fce77c869345bfc94c75894edd3");
  
  const signature = await signer.signData(signData);
  console.log(signature);

  
  const rawSignature = fromSerializedSignature(signature);
  console.log("real sig =", toHEX(rawSignature.signature));
  console.log("real sig pk =", toHEX(rawSignature.pubKey.toBytes()));
  console.log("real sigdata =", toHEX(signData));
/*
  const isValid = await verifyMessage(
    signData,
    signature,
    IntentScope.PersonalMessage,
  );
  console.log(isValid);*/
}

const signTypesArray = async (nftCount) => {
  let privKey = "0x441c0f64eaffbd00a52a8d122caa717378c940598790d8930eb713ef23e77275";
  let keypair = Ed25519Keypair.fromSecretKey(fromHEX(privKey));
  console.log("pubkey =", toHEX(keypair.getPublicKey().toBytes()));
  let types = new Uint8Array([2, 0, 3, 4, 3, 4, 2, 2, 1, 2,   0, 0, 0, 0, 0, 0, 0, 0]);
  types.set(numToUint8Array(101), nftCount);
  let signData = types;
  
  const signature = keypair.signData(signData);
  console.log(signature);
  console.log("hex sig =", toHEX(signature));

  console.log("pk =", keypair.getPublicKey().toBytes());

  let keyStr = "";
  keypair.getPublicKey().toBytes().forEach((v) => keyStr += String.fromCharCode(v));
  console.log('keystr =', keyStr);
  
/*
  const isValid = await verifyMessage(
    signData,
    signature,
    IntentScope.PersonalMessage,
  );
  console.log(isValid);*/
}

const signAndVerify = async () => {
  
  let privKey = "0x441c0f64eaffbd00a52a8d122caa717378c940598790d8930eb713ef23e77275";
  let keypair = Ed25519Keypair.fromSecretKey(fromHEX(privKey));
  console.log("pubkey =", toHEX(keypair.getPublicKey().toBytes()));
  let signMessage = "Sign ME! 3234234";
  const signature = keypair.signData(signData);

  const isValid = await verifyMessage(
    signData,
    signature,
    IntentScope.PersonalMessage,
  );
  console.log(isValid);

}

const main = async () => {
  let nftType = "0x59d312f7032ec92a6427e74d86a32efb65522ffcbf6f98c12c42297e7c6b0193::zombie_house::ZombieInfo";
  const objects = await provider.getOwnedObjects({
      owner: "0xc0f7670e336119c86f4ddf0efc4b964bedaba9baca170593664e9eee31886389"
  });
  let objectIds = [];
  if (objects && objects.data) {
    objects.data.forEach(d => objectIds.push(d.data.objectId));
  }

  let objectDetailList = await provider.multiGetObjects({ ids: objectIds, options: { showType: true } });
  let nftList = [];
  objectDetailList.forEach((obj) => { if(obj.data.type === nftType) nftList.push(obj.data); });

  console.log("nfts =", nftList);
}


main()
// todo: buyzombie_by_token
//~ 3. mint event fetch
//~~ 4. execute transaction

// 1. wallet connect
// 2. wallet sign and verify
/*get_coin_amount(userAddress);
get_coin_amount(userAddress, zptCoinType);
getGameInfoAddress().then(async (gameInfoId) => {
  console.log(gameInfoId)
  // await getZombieAmountFromContract(gameInfoId, userAddress);
  await buyZombieWithToken(gameInfoId, 1);
});
*/
//mergeCoins(userAddress, zptCoinType);
// fetchEvent();


// signTypesArray(10);
registerClaimEvent();
// registerAllEvents();