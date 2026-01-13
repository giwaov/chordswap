import { useState, useEffect, useCallback } from 'react';
import { Contract, formatUnits } from 'ethers';
import { CONTRACTS, FACTORY_ABI, PAIR_ABI, ERC20_ABI } from '../config';

interface PoolAnalyticsProps {
  signer: any;
  isConnected: boolean;
}

interface PoolData {
  pairAddress: string;
  token0: { address: string; symbol: string; reserve: string };
  token1: { address: string; symbol: string; reserve: string };
  totalSupply: string;
  tvl: number;
  volume24h: number;
  fees24h: number;
  apy: number;
}

export default function PoolAnalytics({ signer, isConnected }: PoolAnalyticsProps) {
  const [poolData, setPoolData] = useState<PoolData | null>(null);
  const [loading, setLoading] = useState(true);
  const [userLPBalance, setUserLPBalance] = useState('0');
  const [userShare, setUserShare] = useState(0);

  const fetchPoolData = useCallback(async () => {
    if (!signer) return;

    try {
      setLoading(true);
      const factory = new Contract(CONTRACTS.factory, FACTORY_ABI, signer);
      const pairAddress = await factory.getPair(CONTRACTS.tokenA, CONTRACTS.tokenB);

      if (!pairAddress || pairAddress === '0x0000000000000000000000000000000000000000') {
        setPoolData(null);
        return;
      }

      const pair = new Contract(pairAddress, PAIR_ABI, signer);
      const tokenAContract = new Contract(CONTRACTS.tokenA, ERC20_ABI, signer);
      const tokenBContract = new Contract(CONTRACTS.tokenB, ERC20_ABI, signer);

      const [
        reserves,
        token0Address,
        totalSupply,
        symbolA,
        symbolB,
      ] = await Promise.all([
        pair.getReserves(),
        pair.token0(),
        pair.totalSupply(),
        tokenAContract.symbol(),
        tokenBContract.symbol(),
      ]);

      const [reserve0, reserve1] = reserves;
      const isToken0A = token0Address.toLowerCase() === CONTRACTS.tokenA.toLowerCase();

      const reserveA = isToken0A ? reserve0 : reserve1;
      const reserveB = isToken0A ? reserve1 : reserve0;

      // Calculate TVL (assuming both tokens are $1 for simplicity)
      const tvl = Number(formatUnits(reserveA, 18)) + Number(formatUnits(reserveB, 18));

      // Simulate volume and fees (in production, fetch from indexer)
      const volume24h = tvl * 0.15; // ~15% of TVL daily volume
      const fees24h = volume24h * 0.003; // 0.3% fee

      // Calculate APY from fees
      const dailyReturn = fees24h / tvl;
      const apy = ((1 + dailyReturn) ** 365 - 1) * 100;

      setPoolData({
        pairAddress,
        token0: {
          address: CONTRACTS.tokenA,
          symbol: symbolA,
          reserve: formatUnits(reserveA, 18),
        },
        token1: {
          address: CONTRACTS.tokenB,
          symbol: symbolB,
          reserve: formatUnits(reserveB, 18),
        },
        totalSupply: formatUnits(totalSupply, 18),
        tvl,
        volume24h,
        fees24h,
        apy,
      });

      // Get user LP balance
      if (isConnected) {
        const address = await signer.getAddress();
        const lpBalance = await pair.balanceOf(address);
        const balanceFormatted = formatUnits(lpBalance, 18);
        setUserLPBalance(balanceFormatted);
        
        if (Number(formatUnits(totalSupply, 18)) > 0) {
          setUserShare((Number(balanceFormatted) / Number(formatUnits(totalSupply, 18))) * 100);
        }
      }
    } catch (error) {
      console.error('Failed to fetch pool data:', error);
    } finally {
      setLoading(false);
    }
  }, [signer, isConnected]);

  useEffect(() => {
    fetchPoolData();
    const interval = setInterval(fetchPoolData, 30000);
    return () => clearInterval(interval);
  }, [fetchPoolData]);

  const formatNumber = (num: number, decimals = 2) => {
    if (num >= 1000000) return (num / 1000000).toFixed(decimals) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(decimals) + 'K';
    return num.toFixed(decimals);
  };

  if (loading) {
    return (
      <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
        <div className="flex items-center justify-center py-8">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
        </div>
      </div>
    );
  }

  if (!poolData) {
    return (
      <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
        <h3 className="text-lg font-semibold text-white mb-4">Pool Analytics</h3>
        <p className="text-gray-400 text-center py-8">No liquidity pool found</p>
      </div>
    );
  }

  return (
    <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
      <div className="flex justify-between items-center mb-6">
        <h3 className="text-lg font-semibold text-white">Pool Analytics</h3>
        <button
          onClick={fetchPoolData}
          className="text-gray-400 hover:text-white transition-colors"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </button>
      </div>

      {/* Pool Pair */}
      <div className="flex items-center gap-3 mb-6 p-4 bg-gray-800 rounded-xl">
        <div className="flex -space-x-2">
          <div className="w-10 h-10 rounded-full bg-blue-500 flex items-center justify-center text-white font-bold text-sm border-2 border-gray-800">
            {poolData.token0.symbol[0]}
          </div>
          <div className="w-10 h-10 rounded-full bg-purple-500 flex items-center justify-center text-white font-bold text-sm border-2 border-gray-800">
            {poolData.token1.symbol[0]}
          </div>
        </div>
        <div>
          <p className="text-white font-semibold">
            {poolData.token0.symbol} / {poolData.token1.symbol}
          </p>
          <p className="text-gray-400 text-xs">
            {poolData.pairAddress.slice(0, 6)}...{poolData.pairAddress.slice(-4)}
          </p>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 gap-4 mb-6">
        <div className="bg-gray-800 rounded-xl p-4">
          <p className="text-gray-400 text-xs mb-1">Total Value Locked</p>
          <p className="text-white text-xl font-bold">${formatNumber(poolData.tvl)}</p>
        </div>
        <div className="bg-gray-800 rounded-xl p-4">
          <p className="text-gray-400 text-xs mb-1">24h Volume</p>
          <p className="text-white text-xl font-bold">${formatNumber(poolData.volume24h)}</p>
        </div>
        <div className="bg-gray-800 rounded-xl p-4">
          <p className="text-gray-400 text-xs mb-1">24h Fees</p>
          <p className="text-white text-xl font-bold">${formatNumber(poolData.fees24h)}</p>
        </div>
        <div className="bg-gray-800 rounded-xl p-4">
          <p className="text-gray-400 text-xs mb-1">APY</p>
          <p className="text-green-400 text-xl font-bold">{poolData.apy.toFixed(2)}%</p>
        </div>
      </div>

      {/* Reserves */}
      <div className="mb-6">
        <p className="text-gray-400 text-sm mb-3">Pool Reserves</p>
        <div className="space-y-2">
          <div className="flex justify-between items-center bg-gray-800 rounded-lg p-3">
            <span className="text-white font-medium">{poolData.token0.symbol}</span>
            <span className="text-gray-300">{formatNumber(parseFloat(poolData.token0.reserve))}</span>
          </div>
          <div className="flex justify-between items-center bg-gray-800 rounded-lg p-3">
            <span className="text-white font-medium">{poolData.token1.symbol}</span>
            <span className="text-gray-300">{formatNumber(parseFloat(poolData.token1.reserve))}</span>
          </div>
        </div>
      </div>

      {/* User Position */}
      {isConnected && parseFloat(userLPBalance) > 0 && (
        <div className="bg-gradient-to-r from-blue-500/10 to-purple-500/10 rounded-xl p-4 border border-blue-500/20">
          <p className="text-gray-400 text-sm mb-2">Your Position</p>
          <div className="flex justify-between items-center">
            <div>
              <p className="text-white font-semibold">{parseFloat(userLPBalance).toFixed(6)} LP</p>
              <p className="text-gray-400 text-xs">{userShare.toFixed(4)}% of pool</p>
            </div>
            <div className="text-right">
              <p className="text-white font-semibold">
                ${formatNumber(poolData.tvl * userShare / 100)}
              </p>
              <p className="text-gray-400 text-xs">Estimated value</p>
            </div>
          </div>
        </div>
      )}

      {/* LP Token Info */}
      <div className="mt-4 text-center">
        <p className="text-gray-500 text-xs">
          Total LP Supply: {formatNumber(parseFloat(poolData.totalSupply))} tokens
        </p>
      </div>
    </div>
  );
}
