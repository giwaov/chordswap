import { useState, useEffect, useCallback } from 'react';
import { Contract, parseUnits, formatUnits } from 'ethers';
import { toast } from 'react-hot-toast';
import { CONTRACTS, ERC20_ABI, LIMIT_ORDER_ABI } from '../config';

interface LimitOrdersProps {
  wallet: {
    isConnected: boolean;
    address: string | null;
    signer: any;
    connect: () => void;
  };
}

interface Order {
  id: number;
  tokenIn: string;
  tokenOut: string;
  amountIn: string;
  minAmountOut: string;
  limitPrice: string;
  expiresAt: number;
  isActive: boolean;
}

const TOKENS = [
  { address: CONTRACTS.tokenA, symbol: 'ARCA', name: 'Arc Token A' },
  { address: CONTRACTS.tokenB, symbol: 'ARCB', name: 'Arc Token B' },
];

export default function LimitOrders({ wallet }: LimitOrdersProps) {
  const [tokenInIndex, setTokenInIndex] = useState(0);
  const [tokenOutIndex, setTokenOutIndex] = useState(1);
  const [amountIn, setAmountIn] = useState('');
  const [limitPrice, setLimitPrice] = useState('');
  const [duration, setDuration] = useState('24'); // hours
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(false);
  const [balanceIn, setBalanceIn] = useState('0');

  const tokenIn = TOKENS[tokenInIndex];
  const tokenOut = TOKENS[tokenOutIndex];

  const limitOrderAddress = CONTRACTS.limitOrderBook;

  // Calculate amount out from limit price
  const amountOut = amountIn && limitPrice 
    ? (parseFloat(amountIn) * parseFloat(limitPrice)).toFixed(6)
    : '';

  // Fetch user orders
  const fetchOrders = useCallback(async () => {
    if (!wallet.signer || !wallet.address || !limitOrderAddress) return;

    try {
      const limitOrder = new Contract(limitOrderAddress, LIMIT_ORDER_ABI, wallet.signer);
      const orderIds = await limitOrder.getUserOrders(wallet.address);
      
      const fetchedOrders: Order[] = [];
      
      for (const id of orderIds) {
        const order = await limitOrder.orders(id);
        if (order.isActive) {
          const tokenInSymbol = TOKENS.find(t => t.address.toLowerCase() === order.tokenIn.toLowerCase())?.symbol || 'Unknown';
          const tokenOutSymbol = TOKENS.find(t => t.address.toLowerCase() === order.tokenOut.toLowerCase())?.symbol || 'Unknown';
          
          fetchedOrders.push({
            id: Number(id),
            tokenIn: tokenInSymbol,
            tokenOut: tokenOutSymbol,
            amountIn: formatUnits(order.amountIn, 18),
            minAmountOut: formatUnits(order.minAmountOut, 18),
            limitPrice: (Number(formatUnits(order.minAmountOut, 18)) / Number(formatUnits(order.amountIn, 18))).toFixed(6),
            expiresAt: Number(order.expiresAt) * 1000,
            isActive: order.isActive,
          });
        }
      }
      
      setOrders(fetchedOrders);
    } catch (error) {
      console.error('Failed to fetch orders:', error);
    }
  }, [wallet.signer, wallet.address, limitOrderAddress]);

  // Fetch balance
  const fetchBalance = useCallback(async () => {
    if (!wallet.signer || !wallet.address) return;

    try {
      const token = new Contract(tokenIn.address, ERC20_ABI, wallet.signer);
      const balance = await token.balanceOf(wallet.address);
      setBalanceIn(formatUnits(balance, 18));
    } catch (error) {
      console.error('Failed to fetch balance:', error);
    }
  }, [wallet.signer, wallet.address, tokenIn.address]);

  useEffect(() => {
    if (wallet.isConnected) {
      fetchOrders();
      fetchBalance();
    }
  }, [wallet.isConnected, fetchOrders, fetchBalance]);

  const handleCreateOrder = async () => {
    if (!wallet.signer || !wallet.address || !limitOrderAddress) return;
    if (!amountIn || !limitPrice) return;

    setLoading(true);
    try {
      const token = new Contract(tokenIn.address, ERC20_ABI, wallet.signer);
      const limitOrder = new Contract(limitOrderAddress, LIMIT_ORDER_ABI, wallet.signer);

      const amountInWei = parseUnits(amountIn, 18);
      const minAmountOutWei = parseUnits(amountOut, 18);
      const durationSeconds = parseInt(duration) * 3600; // Convert hours to seconds

      // Approve
      toast.loading('Approving tokens...', { id: 'approve' });
      const allowance = await token.allowance(wallet.address, limitOrderAddress);
      if (allowance < amountInWei) {
        const approveTx = await token.approve(limitOrderAddress, amountInWei);
        await approveTx.wait();
      }
      toast.success('Tokens approved!', { id: 'approve' });

      // Create order
      toast.loading('Creating limit order...', { id: 'order' });
      const tx = await limitOrder.createOrder(
        tokenIn.address,
        tokenOut.address,
        amountInWei,
        minAmountOutWei,
        durationSeconds
      );
      await tx.wait();
      toast.success('Limit order created!', { id: 'order' });

      setAmountIn('');
      setLimitPrice('');
      fetchOrders();
      fetchBalance();
    } catch (error: any) {
      console.error('Failed to create order:', error);
      toast.error(error.reason || 'Failed to create order', { id: 'order' });
    } finally {
      setLoading(false);
    }
  };

  const handleCancelOrder = async (orderId: number) => {
    if (!wallet.signer || !limitOrderAddress) return;

    try {
      toast.loading('Cancelling order...', { id: 'cancel' });
      const limitOrder = new Contract(limitOrderAddress, LIMIT_ORDER_ABI, wallet.signer);
      const tx = await limitOrder.cancelOrder(orderId);
      await tx.wait();
      toast.success('Order cancelled!', { id: 'cancel' });
      fetchOrders();
      fetchBalance();
    } catch (error: any) {
      console.error('Failed to cancel order:', error);
      toast.error(error.reason || 'Failed to cancel order', { id: 'cancel' });
    }
  };

  const switchTokens = () => {
    setTokenInIndex(tokenOutIndex);
    setTokenOutIndex(tokenInIndex);
    setAmountIn('');
    setLimitPrice('');
  };

  const formatTimeRemaining = (expiresAt: number) => {
    const now = Date.now();
    const remaining = expiresAt - now;
    if (remaining <= 0) return 'Expired';
    
    const hours = Math.floor(remaining / (1000 * 60 * 60));
    const minutes = Math.floor((remaining % (1000 * 60 * 60)) / (1000 * 60));
    
    if (hours > 24) return `${Math.floor(hours / 24)}d ${hours % 24}h`;
    return `${hours}h ${minutes}m`;
  };

  // Check if limit order contract is configured
  if (!limitOrderAddress) {
    return (
      <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
        <h2 className="text-xl font-bold text-white mb-4">📝 Limit Orders</h2>
        <div className="text-center py-8">
          <p className="text-gray-400 mb-4">Limit order system not deployed yet.</p>
          <p className="text-gray-500 text-sm">
            Deploy the LimitOrderBook contract and update config.ts
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Create Order */}
      <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
        <h2 className="text-xl font-bold text-white mb-4">📝 Create Limit Order</h2>

        {/* Token In */}
        <div className="bg-gray-800 rounded-xl p-4 mb-2">
          <div className="flex justify-between text-sm text-gray-400 mb-2">
            <span>Sell</span>
            <span>Balance: {parseFloat(balanceIn).toFixed(4)} {tokenIn.symbol}</span>
          </div>
          <div className="flex gap-3 items-center">
            <input
              type="number"
              placeholder="0.0"
              value={amountIn}
              onChange={(e) => setAmountIn(e.target.value)}
              className="flex-1 bg-transparent text-white text-xl font-medium focus:outline-none"
            />
            <button
              onClick={() => setAmountIn(balanceIn)}
              className="px-2 py-1 text-blue-400 text-xs hover:bg-blue-400/20 rounded"
            >
              MAX
            </button>
            <div className="px-3 py-2 bg-gray-700 rounded-lg text-white font-medium">
              {tokenIn.symbol}
            </div>
          </div>
        </div>

        {/* Switch Button */}
        <div className="flex justify-center -my-2 relative z-10">
          <button
            onClick={switchTokens}
            className="p-2 bg-gray-700 border-4 border-gray-900 rounded-xl hover:bg-gray-600 transition-colors"
          >
            <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4" />
            </svg>
          </button>
        </div>

        {/* Limit Price */}
        <div className="bg-gray-800 rounded-xl p-4 mb-4">
          <div className="text-sm text-gray-400 mb-2">
            Limit Price (1 {tokenIn.symbol} = ? {tokenOut.symbol})
          </div>
          <input
            type="number"
            placeholder="0.0"
            value={limitPrice}
            onChange={(e) => setLimitPrice(e.target.value)}
            className="w-full bg-transparent text-white text-xl font-medium focus:outline-none"
          />
        </div>

        {/* You Receive */}
        <div className="bg-gray-800 rounded-xl p-4 mb-4">
          <div className="text-sm text-gray-400 mb-2">You Receive (min)</div>
          <div className="flex justify-between items-center">
            <span className="text-white text-xl font-medium">
              {amountOut || '0.0'}
            </span>
            <div className="px-3 py-2 bg-gray-700 rounded-lg text-white font-medium">
              {tokenOut.symbol}
            </div>
          </div>
        </div>

        {/* Duration */}
        <div className="bg-gray-800 rounded-xl p-4 mb-4">
          <div className="text-sm text-gray-400 mb-2">Order Duration</div>
          <div className="flex gap-2">
            {['1', '6', '24', '168'].map((h) => (
              <button
                key={h}
                onClick={() => setDuration(h)}
                className={`flex-1 py-2 rounded-lg text-sm font-medium transition-colors ${
                  duration === h
                    ? 'bg-blue-500 text-white'
                    : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
                }`}
              >
                {h === '168' ? '7d' : `${h}h`}
              </button>
            ))}
          </div>
        </div>

        {/* Create Button */}
        {!wallet.isConnected ? (
          <button onClick={wallet.connect} className="w-full py-4 bg-blue-500 hover:bg-blue-600 text-white font-bold rounded-xl transition-colors">
            Connect Wallet
          </button>
        ) : (
          <button
            onClick={handleCreateOrder}
            disabled={loading || !amountIn || !limitPrice || parseFloat(amountIn) > parseFloat(balanceIn)}
            className="w-full py-4 bg-blue-500 hover:bg-blue-600 text-white font-bold rounded-xl transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {loading ? 'Creating...' : parseFloat(amountIn) > parseFloat(balanceIn) ? 'Insufficient Balance' : 'Create Limit Order'}
          </button>
        )}
      </div>

      {/* Active Orders */}
      {orders.length > 0 && (
        <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
          <h3 className="text-lg font-semibold text-white mb-4">Your Active Orders</h3>
          <div className="space-y-3">
            {orders.map((order) => (
              <div key={order.id} className="bg-gray-800 rounded-xl p-4">
                <div className="flex justify-between items-start mb-2">
                  <div>
                    <span className="text-white font-medium">
                      {parseFloat(order.amountIn).toFixed(4)} {order.tokenIn}
                    </span>
                    <span className="text-gray-400 mx-2">→</span>
                    <span className="text-white font-medium">
                      {parseFloat(order.minAmountOut).toFixed(4)} {order.tokenOut}
                    </span>
                  </div>
                  <button
                    onClick={() => handleCancelOrder(order.id)}
                    className="text-red-400 hover:text-red-300 text-sm"
                  >
                    Cancel
                  </button>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-400">
                    Limit: {order.limitPrice} {order.tokenOut}/{order.tokenIn}
                  </span>
                  <span className="text-gray-400">
                    Expires: {formatTimeRemaining(order.expiresAt)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
