import { useState } from 'react';
import { Toaster } from 'react-hot-toast';
import { useWallet } from './hooks/useWallet';
import SwapCard from './components/SwapCard';
import LiquidityCard from './components/LiquidityCard';
import Header from './components/Header';

type Tab = 'swap' | 'liquidity';

function App() {
  const wallet = useWallet();
  const [activeTab, setActiveTab] = useState<Tab>('swap');

  return (
    <div className="min-h-screen">
      <Toaster position="top-right" />
      
      <Header wallet={wallet} />

      <main className="container mx-auto px-4 py-12">
        <div className="max-w-lg mx-auto">
          {/* Tab Navigation */}
          <div className="flex gap-2 mb-6">
            <button
              onClick={() => setActiveTab('swap')}
              className={`flex-1 py-3 px-6 rounded-xl font-medium transition-all ${
                activeTab === 'swap'
                  ? 'bg-arc-primary text-white'
                  : 'bg-arc-dark/50 text-gray-400 hover:text-white'
              }`}
            >
              Swap
            </button>
            <button
              onClick={() => setActiveTab('liquidity')}
              className={`flex-1 py-3 px-6 rounded-xl font-medium transition-all ${
                activeTab === 'liquidity'
                  ? 'bg-arc-primary text-white'
                  : 'bg-arc-dark/50 text-gray-400 hover:text-white'
              }`}
            >
              Liquidity
            </button>
          </div>

          {/* Cards */}
          {activeTab === 'swap' ? (
            <SwapCard wallet={wallet} />
          ) : (
            <LiquidityCard wallet={wallet} />
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
