import { useState, useEffect, useCallback } from 'react';
import { Contract, formatUnits, EventLog } from 'ethers';
import { CONTRACTS } from '../config';

interface TransactionHistoryProps {
  wallet: {
    isConnected: boolean;
    address: string | null;
    signer: any;
    provider: any;
  };
}

interface Transaction {
  id: string;
  type: 'swap' | 'add_liquidity' | 'remove_liquidity' | 'limit_order' | 'farm_deposit' | 'farm_withdraw' | 'claim_rewards';
  hash: string;
  timestamp: number;
  details: string;
  tokenIn?: string;
  tokenOut?: string;
  amountIn?: string;
  amountOut?: string;
  status: 'completed' | 'pending' | 'failed';
}

const TX_TYPE_ICONS: Record<string, string> = {
  swap: '🔄',
  add_liquidity: '💧',
  remove_liquidity: '💸',
  limit_order: '📝',
  farm_deposit: '🌾',
  farm_withdraw: '🏧',
  claim_rewards: '🎁',
};

const TX_TYPE_LABELS: Record<string, string> = {
  swap: 'Swap',
  add_liquidity: 'Add Liquidity',
  remove_liquidity: 'Remove Liquidity',
  limit_order: 'Limit Order',
  farm_deposit: 'Farm Deposit',
  farm_withdraw: 'Farm Withdraw',
  claim_rewards: 'Claim Rewards',
};

const TOKEN_SYMBOLS: Record<string, string> = {
  [CONTRACTS.tokenA.toLowerCase()]: 'ARCA',
  [CONTRACTS.tokenB.toLowerCase()]: 'ARCB',
  [CONTRACTS.chordToken.toLowerCase()]: 'CHORD',
};

export default function TransactionHistory({ wallet }: TransactionHistoryProps) {
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<string>('all');

  const getTokenSymbol = (address: string): string => {
    return TOKEN_SYMBOLS[address.toLowerCase()] || address.slice(0, 6) + '...';
  };

  const formatTime = (timestamp: number): string => {
    const now = Date.now() / 1000;
    const diff = now - timestamp;
    
    if (diff < 60) return 'Just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    if (diff < 604800) return `${Math.floor(diff / 86400)}d ago`;
    
    return new Date(timestamp * 1000).toLocaleDateString();
  };

  const fetchTransactionHistory = useCallback(async () => {
    if (!wallet.provider || !wallet.address) {
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      const txs: Transaction[] = [];
      const currentBlock = await wallet.provider.getBlockNumber();
      const fromBlock = Math.max(0, currentBlock - 10000); // Last ~10000 blocks

      // Fetch Swap events from Router
      try {
        const pairAddress = await new Contract(
          CONTRACTS.factory,
          ['function getPair(address,address) view returns (address)'],
          wallet.provider
        ).getPair(CONTRACTS.tokenA, CONTRACTS.tokenB);

        if (pairAddress && pairAddress !== '0x0000000000000000000000000000000000000000') {
          const pair = new Contract(
            pairAddress,
            [
              'event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to)',
              'event Mint(address indexed sender, uint256 amount0, uint256 amount1)',
              'event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to)',
            ],
            wallet.provider
          );

          // Swap events
          const swapFilter = pair.filters.Swap(null, null, null, null, null, wallet.address);
          const swapEvents = await pair.queryFilter(swapFilter, fromBlock);
          
          for (const event of swapEvents) {
            if (!('args' in event)) continue;
            const eventLog = event as EventLog;
            const block = await event.getBlock();
            const args = eventLog.args;
            if (args) {
              const isToken0In = args.amount0In > 0n;
              txs.push({
                id: event.transactionHash + '-swap',
                type: 'swap',
                hash: event.transactionHash,
                timestamp: block.timestamp,
                details: `Swapped ${formatUnits(isToken0In ? args.amount0In : args.amount1In, 18)} ${isToken0In ? 'ARCA' : 'ARCB'} for ${formatUnits(isToken0In ? args.amount1Out : args.amount0Out, 18)} ${isToken0In ? 'ARCB' : 'ARCA'}`,
                amountIn: formatUnits(isToken0In ? args.amount0In : args.amount1In, 18),
                amountOut: formatUnits(isToken0In ? args.amount1Out : args.amount0Out, 18),
                status: 'completed',
              });
            }
          }

          // Mint (Add Liquidity) events
          const mintFilter = pair.filters.Mint(wallet.address);
          const mintEvents = await pair.queryFilter(mintFilter, fromBlock);
          
          for (const event of mintEvents) {
            if (!('args' in event)) continue;
            const eventLog = event as EventLog;
            const block = await event.getBlock();
            const args = eventLog.args;
            if (args) {
              txs.push({
                id: event.transactionHash + '-mint',
                type: 'add_liquidity',
                hash: event.transactionHash,
                timestamp: block.timestamp,
                details: `Added ${formatUnits(args.amount0, 18)} ARCA + ${formatUnits(args.amount1, 18)} ARCB`,
                status: 'completed',
              });
            }
          }

          // Burn (Remove Liquidity) events
          const burnFilter = pair.filters.Burn(null, null, null, wallet.address);
          const burnEvents = await pair.queryFilter(burnFilter, fromBlock);
          
          for (const event of burnEvents) {
            if (!('args' in event)) continue;
            const eventLog = event as EventLog;
            const block = await event.getBlock();
            const args = eventLog.args;
            if (args) {
              txs.push({
                id: event.transactionHash + '-burn',
                type: 'remove_liquidity',
                hash: event.transactionHash,
                timestamp: block.timestamp,
                details: `Removed ${formatUnits(args.amount0, 18)} ARCA + ${formatUnits(args.amount1, 18)} ARCB`,
                status: 'completed',
              });
            }
          }
        }
      } catch (e) {
        console.log('Error fetching pair events:', e);
      }

      // Fetch Limit Order events
      if (CONTRACTS.limitOrderBook) {
        try {
          const limitOrder = new Contract(
            CONTRACTS.limitOrderBook,
            [
              'event OrderCreated(uint256 indexed orderId, address indexed owner, address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint256 expiresAt)',
              'event OrderExecuted(uint256 indexed orderId, address indexed executor, uint256 amountIn, uint256 amountOut, uint256 executorReward)',
              'event OrderCancelled(uint256 indexed orderId, address indexed owner)',
            ],
            wallet.provider
          );

          // Order Created
          const createdFilter = limitOrder.filters.OrderCreated(null, wallet.address);
          const createdEvents = await limitOrder.queryFilter(createdFilter, fromBlock);
          
          for (const event of createdEvents) {
            if (!('args' in event)) continue;
            const eventLog = event as EventLog;
            const block = await event.getBlock();
            const args = eventLog.args;
            if (args) {
              txs.push({
                id: event.transactionHash + '-order-created',
                type: 'limit_order',
                hash: event.transactionHash,
                timestamp: block.timestamp,
                details: `Created limit order: ${formatUnits(args.amountIn, 18)} ${getTokenSymbol(args.tokenIn)} → ${formatUnits(args.minAmountOut, 18)} ${getTokenSymbol(args.tokenOut)}`,
                status: 'completed',
              });
            }
          }

          // Order Cancelled
          const cancelledFilter = limitOrder.filters.OrderCancelled(null, wallet.address);
          const cancelledEvents = await limitOrder.queryFilter(cancelledFilter, fromBlock);
          
          for (const event of cancelledEvents) {
            if (!('args' in event)) continue;
            const eventLog = event as EventLog;
            const block = await event.getBlock();
            const args = eventLog.args;
            if (args) {
              txs.push({
                id: event.transactionHash + '-order-cancelled',
                type: 'limit_order',
                hash: event.transactionHash,
                timestamp: block.timestamp,
                details: `Cancelled limit order #${args.orderId.toString()}`,
                status: 'completed',
              });
            }
          }
        } catch (e) {
          console.log('Error fetching limit order events:', e);
        }
      }

      // Fetch Farm events
      if (CONTRACTS.lpFarm) {
        try {
          const farm = new Contract(
            CONTRACTS.lpFarm,
            [
              'event Deposit(address indexed user, uint256 indexed pid, uint256 amount)',
              'event Withdraw(address indexed user, uint256 indexed pid, uint256 amount)',
              'event Claim(address indexed user, uint256 indexed pid, uint256 amount)',
            ],
            wallet.provider
          );

          // Deposits
          const depositFilter = farm.filters.Deposit(wallet.address);
          const depositEvents = await farm.queryFilter(depositFilter, fromBlock);
          
          for (const event of depositEvents) {
            if (!('args' in event)) continue;
            const eventLog = event as EventLog;
            const block = await event.getBlock();
            const args = eventLog.args;
            if (args && args.amount > 0n) {
              txs.push({
                id: event.transactionHash + '-farm-deposit',
                type: 'farm_deposit',
                hash: event.transactionHash,
                timestamp: block.timestamp,
                details: `Staked ${formatUnits(args.amount, 18)} LP tokens in Pool #${args.pid.toString()}`,
                status: 'completed',
              });
            }
          }

          // Withdrawals
          const withdrawFilter = farm.filters.Withdraw(wallet.address);
          const withdrawEvents = await farm.queryFilter(withdrawFilter, fromBlock);
          
          for (const event of withdrawEvents) {
            if (!('args' in event)) continue;
            const eventLog = event as EventLog;
            const block = await event.getBlock();
            const args = eventLog.args;
            if (args && args.amount > 0n) {
              txs.push({
                id: event.transactionHash + '-farm-withdraw',
                type: 'farm_withdraw',
                hash: event.transactionHash,
                timestamp: block.timestamp,
                details: `Unstaked ${formatUnits(args.amount, 18)} LP tokens from Pool #${args.pid.toString()}`,
                status: 'completed',
              });
            }
          }

          // Claims
          const claimFilter = farm.filters.Claim(wallet.address);
          const claimEvents = await farm.queryFilter(claimFilter, fromBlock);
          
          for (const event of claimEvents) {
            if (!('args' in event)) continue;
            const eventLog = event as EventLog;
            const block = await event.getBlock();
            const args = eventLog.args;
            if (args) {
              txs.push({
                id: event.transactionHash + '-claim',
                type: 'claim_rewards',
                hash: event.transactionHash,
                timestamp: block.timestamp,
                details: `Claimed ${formatUnits(args.amount, 18)} CHORD rewards`,
                status: 'completed',
              });
            }
          }
        } catch (e) {
          console.log('Error fetching farm events:', e);
        }
      }

      // Sort by timestamp descending
      txs.sort((a, b) => b.timestamp - a.timestamp);
      setTransactions(txs);
    } catch (error) {
      console.error('Error fetching transaction history:', error);
    } finally {
      setLoading(false);
    }
  }, [wallet.provider, wallet.address]);

  useEffect(() => {
    fetchTransactionHistory();
  }, [fetchTransactionHistory]);

  const filteredTransactions = filter === 'all' 
    ? transactions 
    : transactions.filter(tx => tx.type === filter);

  const openExplorer = (hash: string) => {
    window.open(`https://testnet.arcscan.app/tx/${hash}`, '_blank');
  };

  if (!wallet.isConnected) {
    return (
      <div className="bg-arc-card rounded-2xl p-6 border border-arc-border">
        <h2 className="text-xl font-bold text-white mb-4">📜 Transaction History</h2>
        <div className="text-center py-12">
          <p className="text-gray-400 mb-4">Connect wallet to view transaction history</p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-arc-card rounded-2xl p-6 border border-arc-border">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-white">📜 Transaction History</h2>
        <button
          onClick={fetchTransactionHistory}
          disabled={loading}
          className="text-arc-primary hover:text-arc-primary/80 transition-colors text-sm"
        >
          {loading ? '⏳ Loading...' : '🔄 Refresh'}
        </button>
      </div>

      {/* Filter Tabs */}
      <div className="flex gap-2 mb-4 overflow-x-auto pb-2">
        {['all', 'swap', 'add_liquidity', 'remove_liquidity', 'limit_order', 'farm_deposit', 'farm_withdraw', 'claim_rewards'].map((type) => (
          <button
            key={type}
            onClick={() => setFilter(type)}
            className={`px-3 py-1.5 rounded-lg text-sm whitespace-nowrap transition-colors ${
              filter === type
                ? 'bg-arc-primary text-white'
                : 'bg-arc-dark/50 text-gray-400 hover:text-white'
            }`}
          >
            {type === 'all' ? '📋 All' : `${TX_TYPE_ICONS[type]} ${TX_TYPE_LABELS[type]}`}
          </button>
        ))}
      </div>

      {/* Transaction List */}
      <div className="space-y-3 max-h-[500px] overflow-y-auto">
        {loading ? (
          <div className="text-center py-12">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-arc-primary mx-auto mb-4"></div>
            <p className="text-gray-400">Loading transactions...</p>
          </div>
        ) : filteredTransactions.length === 0 ? (
          <div className="text-center py-12">
            <p className="text-gray-400 text-4xl mb-4">📭</p>
            <p className="text-gray-400">No transactions found</p>
            <p className="text-gray-500 text-sm mt-2">
              {filter === 'all' 
                ? 'Start trading to see your transaction history'
                : `No ${TX_TYPE_LABELS[filter] || filter} transactions found`}
            </p>
          </div>
        ) : (
          filteredTransactions.map((tx) => (
            <div
              key={tx.id}
              onClick={() => openExplorer(tx.hash)}
              className="bg-arc-dark/30 rounded-xl p-4 hover:bg-arc-dark/50 transition-colors cursor-pointer group"
            >
              <div className="flex items-start justify-between">
                <div className="flex items-start gap-3">
                  <span className="text-2xl">{TX_TYPE_ICONS[tx.type]}</span>
                  <div>
                    <p className="text-white font-medium">{TX_TYPE_LABELS[tx.type]}</p>
                    <p className="text-gray-400 text-sm mt-1">{tx.details}</p>
                  </div>
                </div>
                <div className="text-right">
                  <p className="text-gray-400 text-sm">{formatTime(tx.timestamp)}</p>
                  <div className="flex items-center gap-1 mt-1 opacity-0 group-hover:opacity-100 transition-opacity">
                    <span className="text-arc-primary text-xs">View on Explorer</span>
                    <span className="text-arc-primary">↗</span>
                  </div>
                </div>
              </div>
              
              {/* Transaction Hash */}
              <div className="mt-2 pt-2 border-t border-arc-border/30">
                <p className="text-gray-500 text-xs font-mono">
                  {tx.hash.slice(0, 10)}...{tx.hash.slice(-8)}
                </p>
              </div>
            </div>
          ))
        )}
      </div>

      {/* Summary Stats */}
      {transactions.length > 0 && (
        <div className="mt-4 pt-4 border-t border-arc-border">
          <div className="grid grid-cols-3 gap-4 text-center">
            <div>
              <p className="text-gray-400 text-xs">Total Txs</p>
              <p className="text-white font-bold">{transactions.length}</p>
            </div>
            <div>
              <p className="text-gray-400 text-xs">Swaps</p>
              <p className="text-white font-bold">
                {transactions.filter(t => t.type === 'swap').length}
              </p>
            </div>
            <div>
              <p className="text-gray-400 text-xs">Farm Actions</p>
              <p className="text-white font-bold">
                {transactions.filter(t => t.type.includes('farm') || t.type === 'claim_rewards').length}
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
