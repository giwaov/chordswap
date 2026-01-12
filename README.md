# ChordSwap - AMM on Arc Testnet

ChordSwap is a decentralized exchange (DEX) with Automated Market Maker (AMM) functionality built for the Arc Testnet.

## Features

- **Constant Product AMM**: Uses the x * y = k formula for price discovery
- **Liquidity Pools**: Provide liquidity and earn 0.3% fees on trades
- **Token Swaps**: Swap any ERC20 tokens with instant settlement
- **LP Tokens**: Receive LP tokens representing your share of the pool
- **Multi-hop Swaps**: Route through multiple pools for best pricing

## Arc Testnet Network Details

| Property | Value |
|----------|-------|
| Network | Arc Testnet |
| RPC URL | https://rpc.testnet.arc.network |
| Chain ID | 5042002 |
| Currency | USDC (native gas token) |
| Explorer | https://testnet.arcscan.app |
| Faucet | https://faucet.circle.com |

## Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Wallet funded with testnet USDC from [faucet](https://faucet.circle.com)

## Quick Start

### 1. Install Foundry

```bash
# Download and install foundryup
curl -L https://foundry.paradigm.xyz | bash

# Install forge, cast, anvil, chisel
foundryup
```

### 2. Clone and Setup

```bash
cd arc-dex

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts

# Copy environment file
cp .env.example .env
```

### 3. Configure Environment

Edit `.env` and add your private key:

```env
ARC_TESTNET_RPC_URL="https://rpc.testnet.arc.network"
PRIVATE_KEY="0xyour_private_key_here"
```

### 4. Build Contracts

```bash
forge build
```

### 5. Run Tests

```bash
forge test
```

### 6. Deploy to Arc Testnet

```bash
# Load environment variables
source .env

# Deploy all contracts
forge script script/Deploy.s.sol:DeployArcDex \
  --rpc-url $ARC_TESTNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Contract Architecture

```
arc-dex/
├── src/
│   ├── ArcFactory.sol   # Creates and manages trading pairs
│   ├── ArcPair.sol      # Liquidity pool (constant product AMM)
│   ├── ArcRouter.sol    # User-facing swap/liquidity interface
│   └── ArcToken.sol     # Test ERC20 token with faucet
├── script/
│   └── Deploy.s.sol     # Deployment scripts
├── test/
│   └── ArcDex.t.sol     # Unit tests
└── frontend/            # React frontend (optional)
```

## Usage

### Adding Liquidity

```solidity
// Approve router to spend tokens
tokenA.approve(routerAddress, amountA);
tokenB.approve(routerAddress, amountB);

// Add liquidity
router.addLiquidity(
    tokenA,
    tokenB,
    amountA,
    amountB,
    amountAMin,
    amountBMin,
    recipient,
    deadline
);
```

### Swapping Tokens

```solidity
// Approve router
tokenIn.approve(routerAddress, amountIn);

// Define swap path
address[] memory path = new address[](2);
path[0] = tokenIn;
path[1] = tokenOut;

// Execute swap
router.swapExactTokensForTokens(
    amountIn,
    amountOutMin,
    path,
    recipient,
    deadline
);
```

### Using Cast (CLI)

```bash
# Check pair reserves
cast call $PAIR_ADDRESS "getReserves()" --rpc-url $ARC_TESTNET_RPC_URL

# Get swap quote
cast call $ROUTER_ADDRESS "getAmountOut(uint256,address,address)(uint256)" \
  1000000000000000000 $TOKEN_A $TOKEN_B \
  --rpc-url $ARC_TESTNET_RPC_URL

# Get LP token balance
cast call $PAIR_ADDRESS "balanceOf(address)(uint256)" $YOUR_ADDRESS \
  --rpc-url $ARC_TESTNET_RPC_URL
```

## Fee Structure

- **Swap Fee**: 0.3% (30 basis points)
- **Gas Token**: USDC (Arc's native gas)

## Security Considerations

- This is for **testnet only** - not audited for production
- Never commit your private key to version control
- Use `.env` files for sensitive data
- Consider reentrancy protections (already implemented)

## Wallet Setup (MetaMask)

1. Open MetaMask → Add Network → Add Network Manually
2. Enter:
   - Network Name: `Arc Testnet`
   - RPC URL: `https://rpc.testnet.arc.network`
   - Chain ID: `5042002`
   - Currency Symbol: `USDC`
   - Explorer URL: `https://testnet.arcscan.app`
3. Get testnet USDC from https://faucet.circle.com

## Resources

- [Arc Documentation](https://docs.arc.network/)
- [Arc Explorer](https://testnet.arcscan.app)
- [Circle Faucet](https://faucet.circle.com)
- [Foundry Book](https://book.getfoundry.sh/)

## License

MIT License
