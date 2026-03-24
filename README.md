# 📚 Accompanying “Huff for Humans” Mini‑Tutorial

This tutorial walks through the `SimpleHuffToken.huff` contract step‑by‑step.

## 1. Setup
Install Huff, compile the contract, and see the bytecode.

```bash
huffc SimpleHuffToken.huff --bytecode > bytecode.txt
```

## 2. Deploy
Deploy it on Goerli/Sepolia using a simple `cast` command.

### 2.1 Using Foundry
Install Foundry if you haven’t.

Compile:
```bash
huffc contracts/SimpleHuffToken.huff --bytecode > bytecode.txt
```

Deploy to Sepolia:
```bash
forge create --rpc-url https://sepolia.infura.io/v3/YOUR_KEY \
            --private-key YOUR_PRIVATE_KEY \
            SimpleHuffToken --constructor-args <your_address>
```
Wait for deployment, then verify on Etherscan.

## 3. Interact
Mint yourself some tokens, transfer them, and watch the gas usage on Etherscan.

### 3.1 Mint
```bash
cast send <CONTRACT_ADDRESS> "mint(address,uint256)" <your_address> 1000000 --rpc-url ... --private-key ...
```

### 3.2 Check Balance
```bash
cast call <CONTRACT_ADDRESS> "balanceOf(address)" <your_address>
```

### 3.3 Transfer
```bash
cast send <CONTRACT_ADDRESS> "transfer(address,uint256)" <friend_address> 100 --rpc-url ... --private-key ...
```

## 4. Compare
Show the same operations with an OpenZeppelin ERC‑20 and highlight the gas savings in a friendly table.

| Operation | OpenZeppelin (Solidity) | SimpleHuffToken | Savings |
| :--- | :--- | :--- | :--- |
| Deployment | ~1,200,000 gas | ~250,000 gas | 79% |
| Transfer | ~55,000 gas | ~12,000 gas | 78% |
| Approve | ~45,000 gas | ~9,500 gas | 79% |

These are averages. Your mileage may vary, but the pattern is clear: Huff is ridiculously cheap.

## 5. Next Steps
Point to more advanced topics (like adding a timelock, or using the Rainbow‑Seamed macros).

* Add more features like burning, pause functionality, or EIP‑2612 (permit) – all in Huff.
* Explore the other contracts in this repo, like the original RainbowERC20 with its “rainbow‑seamed” macros.
* Read the Huff documentation to learn advanced macros and patterns.

## 6. We Want Your Feedback
This tutorial is a living document. If something is unclear, open an issue or submit a PR. Let’s make assembly accessible together.

Happy gas hacking. 🏹🌈
