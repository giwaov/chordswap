import { useState } from 'react';
import { Toaster } from 'react-hot-toast';
import { useWallet } from './hooks/useWallet';
import SwapCard from './components/SwapCard';
import LiquidityCard from './components/LiquidityCard';
import PerpCard from './components/PerpCard';
import LimitOrders from './components/LimitOrders';
import FarmCard from './components/FarmCard';
import PriceChart from './components/PriceChart';
import PoolAnalytics from './components/PoolAnalytics';
import Header from './components/Header';
import { CONTRACTS } from './config';

type Tab = 'swap' | 'liquidity' | 'perp' | 'limit' | 'farm';

const TOKENS = [
  { address: CONTRACTS.tokenA, symbol: 'ARCA', name: 'Arc Token A' },
  { address: CONTRACTS.tokenB, symbol: 'ARCB', name: 'Arc Token B' },
];

function App() {
  const wallet = useWallet();
  const [activeTab, setActiveTab] = useState<Tab>('swap');

  return (
    <div className="min-h-screen">
      <Toaster position="top-right" />
      
      <Header wallet={wallet} />

      <main className="container mx-auto px-4 py-8">
        {/* Tab Navigation */}
        <div className="max-w-3xl mx-auto mb-6">
          <div className="flex gap-2 overflow-x-auto pb-2">
            <button
              onClick={() => setActiveTab('swap')}
              className={`py-2 px-4 rounded-xl font-medium transition-all whitespace-nowrap ${
                activeTab === 'swap'
                  ? 'bg-arc-primary text-white'
                  : 'bg-arc-dark/50 text-gray-400 hover:text-white'
              }`}
            >
              🔄 Swap
            </button>
            <button
              onClick={() => setActiveTab('limit')}
              className={`py-2 px-4 rounded-xl font-medium transition-all whitespace-nowrap ${
                activeTab === 'limit'
                  ? 'bg-arc-primary text-white'
                  : 'bg-arc-dark/50 text-gray-400 hover:text-white'
              }`}
            >
              📝 Limit
            </button>
            <button
              onClick={() => setActiveTab('liquidity')}
              className={`py-2 px-4 rounded-xl font-medium transition-all whitespace-nowrap ${
                activeTab === 'liquidity'
                  ? 'bg-arc-primary text-white'
                  : 'bg-arc-dark/50 text-gray-400 hover:text-white'
              }`}
            >
              💧 Liquidity
            </button>
            <button
              onClick={() => setActiveTab('farm')}
              className={`py-2 px-4 rounded-xl font-medium transition-all whitespace-nowrap ${
                activeTab === 'farm'
                  ? 'bg-gradient-to-r from-green-500 to-emerald-500 text-white'
                  : 'bg-arc-dark/50 text-gray-400 hover:text-white'
              }`}
            >
              🌾 Farm
            </button>
            <button
              onClick={() => setActiveTab('perp')}
              className={`py-2 px-4 rounded-xl font-medium transition-all whitespace-nowrap ${
                activeTab === 'perp'
                  ? 'bg-gradient-to-r from-purple-500 to-blue-500 text-white'
                  : 'bg-arc-dark/50 text-gray-400 hover:text-white'
              }`}
            >
              ⚡ Perps
            </button>
          </div>
        </div>

        {/* Content */}
        <div className="max-w-3xl mx-auto">
          {activeTab === 'swap' && (
            <div className="grid lg:grid-cols-2 gap-6">
              <div className="space-y-6">
                <SwapCard wallet={wallet} />
              </div>
              <div className="space-y-6">
                {wallet.signer && (
                  <PriceChart 
                    tokenIn={TOKENS[0]} 
                    tokenOut={TOKENS[1]} 
                    signer={wallet.signer} 
                  />
                )}
                {wallet.signer && (
                  <PoolAnalytics 
                    signer={wallet.signer} 
                    isConnected={wallet.isConnected} 
                  />
                )}
              </div>
            </div>
          )}
          
          {activeTab === 'limit' && (
            <div className="max-w-lg mx-auto">
              <LimitOrders wallet={wallet} />
            </div>
          )}
          
          {activeTab === 'liquidity' && (
            <div className="max-w-lg mx-auto">
              <LiquidityCard wallet={wallet} />
            </div>
          )}
          
          {activeTab === 'farm' && (
            <div className="max-w-lg mx-auto">
              <FarmCard wallet={wallet} />
            </div>
          )}
          
          {activeTab === 'perp' && (
            <div className="max-w-lg mx-auto">
              <PerpCard 
                account={wallet.address || ''} 
                provider={wallet.provider} 
              />
            </div>
          )}

          {/* Network Warning */}
          {wallet.isWrongNetwork && (
            <div className="mt-4 p-4 bg-yellow-500/20 border border-yellow-500/50 rounded-xl text-yellow-200 text-sm text-center">
              Please switch to Arc Testnet (Chain ID: 5042002)
            </div>
          )}

          {/* Info */}
          <div className="mt-8 text-center text-gray-500 text-sm">
            <p>ChordSwap on Arc Testnet</p>
            <p className="mt-1">
              Get testnet USDC from{' '}
              <a
                href="https://faucet.circle.com"
                target="_blank"
                rel="noopener noreferrer"
                className="text-arc-primary hover:underline"
              >
                faucet.circle.com
              </a>
            </p>
          </div>
        </div>
      </main>
    </div>
  );
}

export default App;
