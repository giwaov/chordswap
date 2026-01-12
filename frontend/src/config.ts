// Arc Testnet Configuration
export const ARC_TESTNET = {
  chainId: 5042002,
  chainIdHex: '0x4CEC12',
  name: 'Arc Testnet',
  rpcUrl: 'https://rpc.testnet.arc.network',
  wsUrl: 'wss://rpc.testnet.arc.network',
  explorer: 'https://testnet.arcscan.app',
  currency: {
    name: 'USDC',
    symbol: 'USDC',
    decimals: 18
  }
};

// Contract addresses - UPDATE AFTER DEPLOYMENT
export const CONTRACTS = {
  factory: '0x6ab7D14E741FEb61d9709038609E549e05287278',
  router: '0x4e739222ef41B7f6452058cDA9a2b1d41F4fc04B',
  tokenA: '0x4D4EbDeB51b524c58139323d0D2E00e1D05751Fa',
  tokenB: '0xDB8A2c2A1aFB10e37D1A3F8DFF97374665e47376',
};

// ABI snippets for contract interaction
export const ROUTER_ABI = [
  'function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts)',
  'function swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts)',
  'function addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) external returns (uint256 amountA, uint256 amountB, uint256 liquidity)',
  'function removeLiquidity(address tokenA, address tokenB, uint256 liquidity, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) external returns (uint256 amountA, uint256 amountB)',
  'function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256 amountOut)',
  'function getAmountIn(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256 amountIn)',
  'function getPairInfo(address tokenA, address tokenB) external view returns (address pair, uint256 reserveA, uint256 reserveB, uint256 totalSupply)',
  'function factory() external view returns (address)',
];

export const FACTORY_ABI = [
  'function getPair(address tokenA, address tokenB) external view returns (address pair)',
  'function allPairs(uint256) external view returns (address pair)',
  'function allPairsLength() external view returns (uint256)',
  'function createPair(address tokenA, address tokenB) external returns (address pair)',
];

export const PAIR_ABI = [
  'function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)',
  'function token0() external view returns (address)',
  'function token1() external view returns (address)',
  'function totalSupply() external view returns (uint256)',
  'function balanceOf(address owner) external view returns (uint256)',
  'function approve(address spender, uint256 value) external returns (bool)',
];

export const ERC20_ABI = [
  'function name() external view returns (string)',
  'function symbol() external view returns (string)',
  'function decimals() external view returns (uint8)',
  'function totalSupply() external view returns (uint256)',
  'function balanceOf(address account) external view returns (uint256)',
  'function transfer(address to, uint256 amount) external returns (bool)',
  'function allowance(address owner, address spender) external view returns (uint256)',
  'function approve(address spender, uint256 amount) external returns (bool)',
  'function faucet(uint256 amount) external',
];
