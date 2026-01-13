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
  // Perp DEX contracts
  perpExchange: '0xdE830e296d410f5B605c8D046D761692951Cafee',
  priceOracle: '0x77bF48BC59750D8B2c672538d14d56F11226AAd5',
  // Limit Orders & Farming
  limitOrderBook: '0x1100abe0A74aEE8E1A3a69983bd733c6BEE5E4eF',
  lpFarm: '0xac7E0e57DE96F64AE52EB5e682Ad14f6982d9130',
  chordToken: '0x2A3a79353219645F53c611d46828293b6305E072',
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

// Perp Exchange ABI
export const PERP_EXCHANGE_ABI = [
  'function openPosition(address token, uint256 collateralAmount, uint256 leverage, bool isLong) external',
  'function closePosition(address token) external',
  'function addCollateral(address token, uint256 amount) external',
  'function removeCollateral(address token, uint256 amount) external',
  'function liquidate(address user, address token) external',
  'function getPosition(address user, address token) external view returns (uint256 size, uint256 collateral, uint256 entryPrice, bool isLong, int256 unrealizedPnl, uint256 leverage, uint256 liquidationPrice)',
  'function isLiquidatable(address user, address token) external view returns (bool)',
  'function getMarkets() external view returns (address[] memory)',
  'function getFundingInfo() external view returns (int256 currentFundingRate, uint256 nextFundingTime, uint256 longOI, uint256 shortOI)',
  'function collateralToken() external view returns (address)',
  'function priceOracle() external view returns (address)',
  'function MAX_LEVERAGE() external view returns (uint256)',
  'function TRADING_FEE() external view returns (uint256)',
];

// Price Oracle ABI
export const PRICE_ORACLE_ABI = [
  'function getPrice(address token) external view returns (uint256)',
  'function setPrice(address token, uint256 price) external',
  'function prices(address token) external view returns (uint256)',
  'function lastUpdated(address token) external view returns (uint256)',
];

// Limit Order Book ABI
export const LIMIT_ORDER_ABI = [
  'function createOrder(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint256 duration) external returns (uint256 orderId)',
  'function cancelOrder(uint256 orderId) external',
  'function executeOrder(uint256 orderId) external',
  'function claimExpired(uint256 orderId) external',
  'function getUserOrders(address user) external view returns (uint256[] memory)',
  'function getActiveOrders(address user) external view returns (tuple(address owner, address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint256 createdAt, uint256 expiresAt, bool isActive)[] memory)',
  'function canExecute(uint256 orderId) external view returns (bool)',
  'function getOrderLimitPrice(uint256 orderId) external view returns (uint256)',
  'function orders(uint256 orderId) external view returns (address owner, address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint256 createdAt, uint256 expiresAt, bool isActive)',
];

// LP Farm ABI
export const LP_FARM_ABI = [
  'function poolLength() external view returns (uint256)',
  'function pendingReward(uint256 pid, address user) external view returns (uint256)',
  'function getPoolInfo(uint256 pid) external view returns (address lpToken, uint256 allocPoint, uint256 totalStaked, uint256 depositFee, uint256 accRewardPerShare)',
  'function getUserInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 pending, uint256 lastStakeTime)',
  'function deposit(uint256 pid, uint256 amount) external',
  'function withdraw(uint256 pid, uint256 amount) external',
  'function claim(uint256 pid) external',
  'function emergencyWithdraw(uint256 pid) external',
  'function rewardPerSecond() external view returns (uint256)',
  'function totalAllocPoint() external view returns (uint256)',
];
