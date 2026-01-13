import { useState, useEffect, useCallback } from 'react';
import { Contract, formatUnits } from 'ethers';
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';
import { CONTRACTS, FACTORY_ABI, PAIR_ABI } from '../config';

interface PriceChartProps {
  tokenIn: { address: string; symbol: string };
  tokenOut: { address: string; symbol: string };
  signer: any;
}

interface PricePoint {
  time: string;
  timestamp: number;
  price: number;
}

export default function PriceChart({ tokenIn, tokenOut, signer }: PriceChartProps) {
  const [priceHistory, setPriceHistory] = useState<PricePoint[]>([]);
  const [currentPrice, setCurrentPrice] = useState<number>(0);
  const [priceChange, setPriceChange] = useState<number>(0);
  const [timeframe, setTimeframe] = useState<'1H' | '24H' | '7D'>('24H');
  const [loading, setLoading] = useState(true);

  // Fetch current price from pool reserves
  const fetchCurrentPrice = useCallback(async () => {
    if (!signer) return 0;

    try {
      const factory = new Contract(CONTRACTS.factory, FACTORY_ABI, signer);
      const pairAddress = await factory.getPair(tokenIn.address, tokenOut.address);
      
      if (!pairAddress || pairAddress === '0x0000000000000000000000000000000000000000') {
        return 0;
      }

      const pair = new Contract(pairAddress, PAIR_ABI, signer);
      const [reserve0, reserve1] = await pair.getReserves();
      const token0 = await pair.token0();

      const [reserveIn, reserveOut] = tokenIn.address.toLowerCase() === token0.toLowerCase()
        ? [reserve0, reserve1]
        : [reserve1, reserve0];

      const price = Number(formatUnits(reserveOut, 18)) / Number(formatUnits(reserveIn, 18));
      return price;
    } catch (error) {
      console.error('Failed to fetch price:', error);
      return 0;
    }
  }, [signer, tokenIn.address, tokenOut.address]);

  // Generate simulated historical data based on current price
  // In production, you would fetch this from an indexer or subgraph
  const generatePriceHistory = useCallback((currentPrice: number, timeframe: string) => {
    const now = Date.now();
    const points: PricePoint[] = [];
    
    let intervals: number;
    let intervalMs: number;
    
    switch (timeframe) {
      case '1H':
        intervals = 60;
        intervalMs = 60 * 1000; // 1 minute
        break;
      case '7D':
        intervals = 168;
        intervalMs = 60 * 60 * 1000; // 1 hour
        break;
      default: // 24H
        intervals = 96;
        intervalMs = 15 * 60 * 1000; // 15 minutes
    }

    // Generate realistic price movement
    let price = currentPrice;
    const volatility = 0.02; // 2% volatility
    
    for (let i = intervals; i >= 0; i--) {
      const timestamp = now - (i * intervalMs);
      const date = new Date(timestamp);
      
      // Random walk with mean reversion towards current price
      const random = (Math.random() - 0.5) * 2;
      const meanReversion = (currentPrice - price) * 0.1;
      price = price * (1 + random * volatility) + meanReversion;
      price = Math.max(price, currentPrice * 0.8); // Floor at 80% of current
      price = Math.min(price, currentPrice * 1.2); // Cap at 120% of current
      
      let timeStr: string;
      if (timeframe === '1H') {
        timeStr = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      } else if (timeframe === '7D') {
        timeStr = date.toLocaleDateString([], { weekday: 'short', hour: '2-digit' });
      } else {
        timeStr = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      }
      
      points.push({
        time: timeStr,
        timestamp,
        price: Number(price.toFixed(6)),
      });
    }
    
    // Ensure last point is current price
    if (points.length > 0) {
      points[points.length - 1].price = currentPrice;
    }
    
    return points;
  }, []);

  useEffect(() => {
    const loadData = async () => {
      setLoading(true);
      const price = await fetchCurrentPrice();
      setCurrentPrice(price);
      
      if (price > 0) {
        const history = generatePriceHistory(price, timeframe);
        setPriceHistory(history);
        
        // Calculate price change
        if (history.length > 1) {
          const firstPrice = history[0].price;
          const change = ((price - firstPrice) / firstPrice) * 100;
          setPriceChange(change);
        }
      }
      
      setLoading(false);
    };

    loadData();
    
    // Refresh every 30 seconds
    const interval = setInterval(loadData, 30000);
    return () => clearInterval(interval);
  }, [fetchCurrentPrice, generatePriceHistory, timeframe]);

  const formatPrice = (value: number) => {
    if (value >= 1) return value.toFixed(4);
    if (value >= 0.01) return value.toFixed(6);
    return value.toFixed(8);
  };

  const minPrice = Math.min(...priceHistory.map(p => p.price)) * 0.995;
  const maxPrice = Math.max(...priceHistory.map(p => p.price)) * 1.005;

  return (
    <div className="bg-gray-900 rounded-2xl p-4 border border-gray-800">
      {/* Header */}
      <div className="flex justify-between items-start mb-4">
        <div>
          <h3 className="text-lg font-semibold text-white">
            {tokenIn.symbol}/{tokenOut.symbol}
          </h3>
          <div className="flex items-baseline gap-2">
            <span className="text-2xl font-bold text-white">
              {loading ? '...' : formatPrice(currentPrice)}
            </span>
            <span className={`text-sm font-medium ${priceChange >= 0 ? 'text-green-400' : 'text-red-400'}`}>
              {priceChange >= 0 ? '+' : ''}{priceChange.toFixed(2)}%
            </span>
          </div>
        </div>
        
        {/* Timeframe Selector */}
        <div className="flex gap-1 bg-gray-800 rounded-lg p-1">
          {(['1H', '24H', '7D'] as const).map((tf) => (
            <button
              key={tf}
              onClick={() => setTimeframe(tf)}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                timeframe === tf
                  ? 'bg-blue-500 text-white'
                  : 'text-gray-400 hover:text-white'
              }`}
            >
              {tf}
            </button>
          ))}
        </div>
      </div>

      {/* Chart */}
      <div className="h-48">
        {loading ? (
          <div className="flex items-center justify-center h-full">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
          </div>
        ) : priceHistory.length === 0 ? (
          <div className="flex items-center justify-center h-full text-gray-500">
            No price data available
          </div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={priceHistory}>
              <defs>
                <linearGradient id="priceGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop
                    offset="5%"
                    stopColor={priceChange >= 0 ? '#10b981' : '#ef4444'}
                    stopOpacity={0.3}
                  />
                  <stop
                    offset="95%"
                    stopColor={priceChange >= 0 ? '#10b981' : '#ef4444'}
                    stopOpacity={0}
                  />
                </linearGradient>
              </defs>
              <XAxis
                dataKey="time"
                axisLine={false}
                tickLine={false}
                tick={{ fill: '#6b7280', fontSize: 10 }}
                interval="preserveStartEnd"
                minTickGap={50}
              />
              <YAxis
                domain={[minPrice, maxPrice]}
                axisLine={false}
                tickLine={false}
                tick={{ fill: '#6b7280', fontSize: 10 }}
                width={60}
                tickFormatter={(value) => formatPrice(value)}
              />
              <Tooltip
                contentStyle={{
                  backgroundColor: '#1f2937',
                  border: '1px solid #374151',
                  borderRadius: '8px',
                }}
                labelStyle={{ color: '#9ca3af' }}
                itemStyle={{ color: '#fff' }}
                formatter={(value: number | undefined) => value !== undefined ? [formatPrice(value), 'Price'] : ['', 'Price']}
              />
              <Area
                type="monotone"
                dataKey="price"
                stroke={priceChange >= 0 ? '#10b981' : '#ef4444'}
                strokeWidth={2}
                fill="url(#priceGradient)"
              />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-4 mt-4 pt-4 border-t border-gray-800">
        <div>
          <p className="text-xs text-gray-500">High</p>
          <p className="text-sm text-white font-medium">
            {priceHistory.length > 0 ? formatPrice(Math.max(...priceHistory.map(p => p.price))) : '-'}
          </p>
        </div>
        <div>
          <p className="text-xs text-gray-500">Low</p>
          <p className="text-sm text-white font-medium">
            {priceHistory.length > 0 ? formatPrice(Math.min(...priceHistory.map(p => p.price))) : '-'}
          </p>
        </div>
        <div>
          <p className="text-xs text-gray-500">Avg</p>
          <p className="text-sm text-white font-medium">
            {priceHistory.length > 0 
              ? formatPrice(priceHistory.reduce((a, b) => a + b.price, 0) / priceHistory.length)
              : '-'}
          </p>
        </div>
      </div>
    </div>
  );
}
