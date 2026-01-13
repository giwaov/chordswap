import { useState } from 'react';
import { useLending, MarketData } from '../hooks/useLending';
import toast from 'react-hot-toast';
import { ethers } from 'ethers';

interface LendingCardProps {
  wallet: {
    provider: ethers.BrowserProvider | null;
    address: string | null;
    isConnected: boolean;
  };
}

type ActionMode = 'supply' | 'withdraw' | 'borrow' | 'repay';

export default function LendingCard({ wallet }: LendingCardProps) {
  const {
    markets,
    userAccount,
    loading,
    refresh,
    supply,
    withdraw,
    borrow,
    repay,
    toggleCollateral,
    mintTestTokens,
  } = useLending(wallet.provider, wallet.address);

  const [selectedMarket, setSelectedMarket] = useState<MarketData | null>(null);
  const [actionMode, setActionMode] = useState<ActionMode>('supply');
  const [amount, setAmount] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);
  const [showModal, setShowModal] = useState(false);

  const handleAction = async () => {
    if (!selectedMarket || !amount || parseFloat(amount) <= 0) {
      toast.error('Enter a valid amount');
      return;
    }

    setIsProcessing(true);
    try {
      switch (actionMode) {
        case 'supply':
          await supply(selectedMarket.address, amount, selectedMarket.decimals);
          toast.success(`Supplied ${amount} ${selectedMarket.symbol}`);
          break;
        case 'withdraw':
          await withdraw(selectedMarket.address, amount, selectedMarket.decimals);
          toast.success(`Withdrew ${amount} ${selectedMarket.symbol}`);
          break;
        case 'borrow':
          await borrow(selectedMarket.address, amount, selectedMarket.decimals);
          toast.success(`Borrowed ${amount} ${selectedMarket.symbol}`);
          break;
        case 'repay':
          await repay(selectedMarket.address, amount, selectedMarket.decimals);
          toast.success(`Repaid ${amount} ${selectedMarket.symbol}`);
          break;
      }
      setAmount('');
      setShowModal(false);
    } catch (err: any) {
      console.error(err);
      toast.error(err.reason || err.message || 'Transaction failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleToggleCollateral = async (market: MarketData) => {
    setIsProcessing(true);
    try {
      await toggleCollateral(market.address, !market.isCollateralEnabled);
      toast.success(
        market.isCollateralEnabled 
          ? `Disabled ${market.symbol} as collateral`
          : `Enabled ${market.symbol} as collateral`
      );
    } catch (err: any) {
      console.error(err);
      toast.error(err.reason || err.message || 'Failed to toggle collateral');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleMint = async (market: MarketData) => {
    setIsProcessing(true);
    try {
      await mintTestTokens(market.address, market.decimals);
      toast.success(`Minted test ${market.symbol} tokens`);
    } catch (err: any) {
      console.error(err);
      toast.error(err.reason || err.message || 'Failed to mint tokens');
    } finally {
      setIsProcessing(false);
    }
  };

  const openModal = (market: MarketData, mode: ActionMode) => {
    setSelectedMarket(market);
    setActionMode(mode);
    setAmount('');
    setShowModal(true);
  };

  const getMaxAmount = () => {
    if (!selectedMarket) return '0';
    switch (actionMode) {
      case 'supply':
        return selectedMarket.walletBalance;
      case 'withdraw':
        return selectedMarket.suppliedBalance;
      case 'borrow':
        return selectedMarket.availableLiquidity;
      case 'repay':
        return Math.min(
          parseFloat(selectedMarket.walletBalance),
          parseFloat(selectedMarket.borrowedBalance)
        ).toString();
      default:
        return '0';
    }
  };

  const formatValue = (value: string, price: string) => {
    const usdValue = parseFloat(value) * parseFloat(price);
    return usdValue.toLocaleString('en-US', { style: 'currency', currency: 'USD' });
  };

  const getHealthFactorColor = (hf: string) => {
    if (hf === '∞') return 'text-green-400';
    const value = parseFloat(hf);
    if (value > 2) return 'text-green-400';
    if (value > 1.5) return 'text-yellow-400';
    if (value > 1.1) return 'text-orange-400';
    return 'text-red-400';
  };

  return (
    <div className="space-y-6">
      {/* Hero Section */}
      <div className="bg-gradient-to-r from-arc-primary/10 via-arc-dark/50 to-arc-secondary/10 rounded-2xl p-6 border border-arc-primary/30 mb-6">
        <div className="flex items-center gap-3 mb-2">
          <span className="text-3xl">🏦</span>
          <h1 className="text-2xl font-bold text-white">CredArc</h1>
          <span className="px-2 py-0.5 text-xs bg-arc-primary/20 text-arc-primary rounded-full">Lending</span>
        </div>
        <p className="text-gray-400 mb-4">
          The premier lending protocol on Arc Network. Earn yield on your crypto assets or borrow against your holdings with competitive rates. 
          Powered by dynamic interest rates and robust liquidation mechanisms.
        </p>
        <div className="flex flex-wrap gap-4 text-sm">
          <div className="flex items-center gap-2 text-gray-300">
            <span className="w-2 h-2 bg-green-400 rounded-full"></span>
            Non-custodial & Permissionless
          </div>
          <div className="flex items-center gap-2 text-gray-300">
            <span className="w-2 h-2 bg-blue-400 rounded-full"></span>
            Dynamic Interest Rates
          </div>
          <div className="flex items-center gap-2 text-gray-300">
            <span className="w-2 h-2 bg-purple-400 rounded-full"></span>
            Flash Loans Available
          </div>
        </div>
      </div>

      {/* User Account Summary */}
      {wallet.isConnected && userAccount && (
        <div className="bg-gradient-to-r from-arc-dark/80 to-arc-darker/80 rounded-2xl p-6 border border-arc-primary/20">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-xl font-bold text-white">Your Position</h2>
              <p className="text-gray-500 text-sm">Overview of your lending activity</p>
            </div>
            <button
              onClick={refresh}
              disabled={loading}
              className="p-2 rounded-lg bg-arc-dark/50 hover:bg-arc-dark text-gray-400 hover:text-white transition-all"
            >
              🔄
            </button>
          </div>
          
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="bg-arc-dark/50 rounded-xl p-4">
              <div className="text-gray-400 text-sm">Total Supplied</div>
              <div className="text-xl font-bold text-white">
                ${parseFloat(userAccount.totalCollateralValue).toLocaleString(undefined, { maximumFractionDigits: 2 })}
              </div>
            </div>
            <div className="bg-arc-dark/50 rounded-xl p-4">
              <div className="text-gray-400 text-sm">Total Borrowed</div>
              <div className="text-xl font-bold text-white">
                ${parseFloat(userAccount.totalBorrowValue).toLocaleString(undefined, { maximumFractionDigits: 2 })}
              </div>
            </div>
            <div className="bg-arc-dark/50 rounded-xl p-4">
              <div className="text-gray-400 text-sm">Available to Borrow</div>
              <div className="text-xl font-bold text-green-400">
                ${parseFloat(userAccount.availableBorrowValue).toLocaleString(undefined, { maximumFractionDigits: 2 })}
              </div>
            </div>
            <div className="bg-arc-dark/50 rounded-xl p-4">
              <div className="text-gray-400 text-sm">Health Factor</div>
              <div className={`text-xl font-bold ${getHealthFactorColor(userAccount.healthFactor)}`}>
                {userAccount.healthFactor}
              </div>
            </div>
          </div>

          {parseFloat(userAccount.healthFactor) < 1.5 && userAccount.healthFactor !== '∞' && (
            <div className="mt-4 p-3 bg-red-500/20 border border-red-500/50 rounded-lg">
              <p className="text-red-400 text-sm">
                ⚠️ Your health factor is low. Add collateral or repay debt to avoid liquidation.
              </p>
            </div>
          )}
        </div>
      )}

      {/* Markets */}
      <div className="bg-arc-dark/50 rounded-2xl p-6 border border-gray-800">
        <div className="flex items-center justify-between mb-2">
          <h2 className="text-xl font-bold text-white">💰 Lending Markets</h2>
          {loading && <span className="text-gray-400 text-sm">Loading...</span>}
        </div>
        <p className="text-gray-500 text-sm mb-6">
          Supply assets to earn interest or use them as collateral to borrow. Interest rates adjust dynamically based on market utilization.
        </p>

        <div className="space-y-4">
          {markets.map((market) => (
            <div
              key={market.address}
              className="bg-arc-darker/50 rounded-xl p-4 border border-gray-800 hover:border-arc-primary/50 transition-all"
            >
              {/* Market Header */}
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-3">
                  <div className={`w-10 h-10 rounded-full bg-gradient-to-r ${market.color} flex items-center justify-center text-xl`}>
                    {market.icon}
                  </div>
                  <div>
                    <div className="font-bold text-white">{market.symbol}</div>
                    <div className="text-gray-400 text-sm">{market.name}</div>
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-gray-400 text-sm">Price</div>
                  <div className="font-medium text-white">
                    ${parseFloat(market.price).toLocaleString(undefined, { maximumFractionDigits: 2 })}
                  </div>
                </div>
              </div>

              {/* Market Stats */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
                <div>
                  <div className="text-gray-500 text-xs">Total Supply</div>
                  <div className="text-white font-medium">
                    {parseFloat(market.totalSupply).toLocaleString(undefined, { maximumFractionDigits: 2 })}
                  </div>
                  <div className="text-gray-500 text-xs">
                    {formatValue(market.totalSupply, market.price)}
                  </div>
                </div>
                <div>
                  <div className="text-gray-500 text-xs">Total Borrowed</div>
                  <div className="text-white font-medium">
                    {parseFloat(market.totalBorrows).toLocaleString(undefined, { maximumFractionDigits: 2 })}
                  </div>
                  <div className="text-gray-500 text-xs">
                    {formatValue(market.totalBorrows, market.price)}
                  </div>
                </div>
                <div>
                  <div className="text-gray-500 text-xs">Supply APR</div>
                  <div className="text-green-400 font-medium">{market.supplyAPR}%</div>
                </div>
                <div>
                  <div className="text-gray-500 text-xs">Borrow APR</div>
                  <div className="text-orange-400 font-medium">{market.borrowAPR}%</div>
                </div>
              </div>

              {/* Utilization Bar */}
              <div className="mb-4">
                <div className="flex justify-between text-xs text-gray-500 mb-1">
                  <span>Utilization</span>
                  <span>{market.utilization}%</span>
                </div>
                <div className="h-2 bg-gray-700 rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full bg-gradient-to-r ${
                      parseFloat(market.utilization) > 80 
                        ? 'from-red-500 to-orange-500' 
                        : 'from-arc-primary to-arc-secondary'
                    }`}
                    style={{ width: `${Math.min(parseFloat(market.utilization), 100)}%` }}
                  />
                </div>
              </div>

              {/* User Position in this market */}
              {wallet.isConnected && (
                <div className="bg-arc-dark/50 rounded-lg p-3 mb-4">
                  <div className="grid grid-cols-3 gap-4 text-sm">
                    <div>
                      <div className="text-gray-500 text-xs">Wallet</div>
                      <div className="text-white">
                        {parseFloat(market.walletBalance).toLocaleString(undefined, { maximumFractionDigits: 4 })} {market.symbol}
                      </div>
                    </div>
                    <div>
                      <div className="text-gray-500 text-xs">Supplied</div>
                      <div className="text-green-400">
                        {parseFloat(market.suppliedBalance).toLocaleString(undefined, { maximumFractionDigits: 4 })} {market.symbol}
                      </div>
                    </div>
                    <div>
                      <div className="text-gray-500 text-xs">Borrowed</div>
                      <div className="text-orange-400">
                        {parseFloat(market.borrowedBalance).toLocaleString(undefined, { maximumFractionDigits: 4 })} {market.symbol}
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* Action Buttons */}
              {wallet.isConnected ? (
                <div className="flex flex-wrap gap-2">
                  <button
                    onClick={() => openModal(market, 'supply')}
                    className="flex-1 py-2 px-4 rounded-lg bg-green-500/20 text-green-400 hover:bg-green-500/30 transition-all font-medium text-sm"
                  >
                    Supply
                  </button>
                  <button
                    onClick={() => openModal(market, 'withdraw')}
                    disabled={parseFloat(market.suppliedBalance) === 0}
                    className="flex-1 py-2 px-4 rounded-lg bg-blue-500/20 text-blue-400 hover:bg-blue-500/30 transition-all font-medium text-sm disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Withdraw
                  </button>
                  <button
                    onClick={() => openModal(market, 'borrow')}
                    className="flex-1 py-2 px-4 rounded-lg bg-orange-500/20 text-orange-400 hover:bg-orange-500/30 transition-all font-medium text-sm"
                  >
                    Borrow
                  </button>
                  <button
                    onClick={() => openModal(market, 'repay')}
                    disabled={parseFloat(market.borrowedBalance) === 0}
                    className="flex-1 py-2 px-4 rounded-lg bg-purple-500/20 text-purple-400 hover:bg-purple-500/30 transition-all font-medium text-sm disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Repay
                  </button>
                  <button
                    onClick={() => handleToggleCollateral(market)}
                    disabled={isProcessing}
                    className={`py-2 px-4 rounded-lg transition-all font-medium text-sm ${
                      market.isCollateralEnabled
                        ? 'bg-arc-primary/20 text-arc-primary'
                        : 'bg-gray-500/20 text-gray-400'
                    }`}
                  >
                    {market.isCollateralEnabled ? '✓ Collateral' : 'Enable Collateral'}
                  </button>
                  <button
                    onClick={() => handleMint(market)}
                    disabled={isProcessing}
                    className="py-2 px-4 rounded-lg bg-yellow-500/20 text-yellow-400 hover:bg-yellow-500/30 transition-all font-medium text-sm"
                    title="Get test tokens"
                  >
                    🚰 Faucet
                  </button>
                </div>
              ) : (
                <div className="text-center py-3 text-gray-500 text-sm">
                  Connect wallet to interact
                </div>
              )}

              {/* LTV Info */}
              <div className="mt-3 flex gap-4 text-xs text-gray-500">
                <span>LTV: {market.collateralFactor}%</span>
                <span>Liquidation: {market.liquidationThreshold}%</span>
              </div>
            </div>
          ))}

          {markets.length === 0 && !loading && (
            <div className="text-center py-8 text-gray-500">
              No markets available
            </div>
          )}
        </div>
      </div>

      {/* Action Modal */}
      {showModal && selectedMarket && (
        <div className="fixed inset-0 bg-black/80 flex items-center justify-center z-50 p-4">
          <div className="bg-arc-darker rounded-2xl p-6 max-w-md w-full border border-gray-800">
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-xl font-bold text-white capitalize">
                {actionMode} {selectedMarket.symbol}
              </h3>
              <button
                onClick={() => setShowModal(false)}
                className="text-gray-400 hover:text-white text-2xl"
              >
                ×
              </button>
            </div>

            <div className="mb-6">
              <div className="flex items-center justify-between mb-2">
                <span className="text-gray-400">Amount</span>
                <span className="text-gray-500 text-sm">
                  Max: {parseFloat(getMaxAmount()).toLocaleString(undefined, { maximumFractionDigits: 6 })} {selectedMarket.symbol}
                </span>
              </div>
              <div className="relative">
                <input
                  type="number"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder="0.00"
                  className="w-full bg-arc-dark rounded-xl px-4 py-3 text-white text-lg outline-none border border-gray-700 focus:border-arc-primary"
                />
                <button
                  onClick={() => setAmount(getMaxAmount())}
                  className="absolute right-3 top-1/2 -translate-y-1/2 px-3 py-1 bg-arc-primary/20 text-arc-primary rounded-lg text-sm hover:bg-arc-primary/30"
                >
                  MAX
                </button>
              </div>
              {amount && (
                <div className="mt-2 text-gray-500 text-sm">
                  ≈ {formatValue(amount, selectedMarket.price)}
                </div>
              )}
            </div>

            {/* Action-specific info */}
            <div className="bg-arc-dark/50 rounded-xl p-4 mb-6">
              {actionMode === 'supply' && (
                <>
                  <div className="flex justify-between text-sm mb-2">
                    <span className="text-gray-400">Supply APR</span>
                    <span className="text-green-400">{selectedMarket.supplyAPR}%</span>
                  </div>
                  <p className="text-gray-500 text-xs">You'll receive aTokens representing your deposit. Interest accrues automatically.</p>
                </>
              )}
              {actionMode === 'borrow' && (
                <>
                  <div className="flex justify-between text-sm mb-2">
                    <span className="text-gray-400">Borrow APR</span>
                    <span className="text-orange-400">{selectedMarket.borrowAPR}%</span>
                  </div>
                  <div className="flex justify-between text-sm mb-2">
                    <span className="text-gray-400">Available Liquidity</span>
                    <span className="text-white">{parseFloat(selectedMarket.availableLiquidity).toLocaleString()}</span>
                  </div>
                  <p className="text-gray-500 text-xs">Ensure you have sufficient collateral enabled. Monitor your health factor after borrowing.</p>
                </>
              )}
              {(actionMode === 'withdraw' || actionMode === 'repay') && (
                <div className="flex justify-between text-sm">
                  <span className="text-gray-400">
                    {actionMode === 'withdraw' ? 'Your Supply' : 'Your Debt'}
                  </span>
                  <span className="text-white">
                    {actionMode === 'withdraw' 
                      ? parseFloat(selectedMarket.suppliedBalance).toLocaleString()
                      : parseFloat(selectedMarket.borrowedBalance).toLocaleString()
                    } {selectedMarket.symbol}
                  </span>
                </div>
              )}
            </div>

            <button
              onClick={handleAction}
              disabled={isProcessing || !amount || parseFloat(amount) <= 0}
              className={`w-full py-4 rounded-xl font-bold text-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed ${
                actionMode === 'supply' 
                  ? 'bg-gradient-to-r from-green-500 to-emerald-500 text-white hover:from-green-600 hover:to-emerald-600'
                  : actionMode === 'borrow'
                  ? 'bg-gradient-to-r from-orange-500 to-amber-500 text-white hover:from-orange-600 hover:to-amber-600'
                  : 'bg-gradient-to-r from-arc-primary to-arc-secondary text-white hover:from-arc-primary/90 hover:to-arc-secondary/90'
              }`}
            >
              {isProcessing ? 'Processing...' : `${actionMode.charAt(0).toUpperCase() + actionMode.slice(1)} ${selectedMarket.symbol}`}
            </button>
          </div>
        </div>
      )}

      {/* Info Box */}
      <div className="bg-arc-dark/30 rounded-xl p-5 border border-gray-800">
        <h4 className="text-white font-medium mb-3">📚 How CredArc Works</h4>
        <div className="grid md:grid-cols-2 gap-4 text-sm">
          <div className="space-y-2">
            <div className="flex items-start gap-2">
              <span className="text-green-400 mt-0.5">●</span>
              <div>
                <strong className="text-white">Supply & Earn</strong>
                <p className="text-gray-400">Deposit assets to earn passive yield. APR adjusts based on utilization.</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <span className="text-blue-400 mt-0.5">●</span>
              <div>
                <strong className="text-white">Enable Collateral</strong>
                <p className="text-gray-400">Toggle your supplied assets as collateral to unlock borrowing power.</p>
              </div>
            </div>
          </div>
          <div className="space-y-2">
            <div className="flex items-start gap-2">
              <span className="text-orange-400 mt-0.5">●</span>
              <div>
                <strong className="text-white">Borrow Assets</strong>
                <p className="text-gray-400">Borrow up to your LTV limit. Monitor your health factor to avoid liquidation.</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <span className="text-purple-400 mt-0.5">●</span>
              <div>
                <strong className="text-white">Stay Safe</strong>
                <p className="text-gray-400">Keep Health Factor above 1.0. Repay debt or add collateral if it drops.</p>
              </div>
            </div>
          </div>
        </div>
        <div className="mt-4 pt-4 border-t border-gray-700">
          <p className="text-gray-500 text-xs">
            💡 <strong>Testnet Mode:</strong> Use the 🚰 Faucet buttons to get free test tokens and explore the protocol risk-free.
          </p>
        </div>
      </div>

      {/* Protocol Stats */}
      <div className="bg-arc-dark/20 rounded-xl p-4 border border-gray-800/50">
        <div className="flex flex-wrap justify-center gap-8 text-center text-sm">
          <div>
            <div className="text-gray-500">Protocol</div>
            <div className="text-white font-medium">CredArc v1.0</div>
          </div>
          <div>
            <div className="text-gray-500">Network</div>
            <div className="text-white font-medium">Arc Testnet</div>
          </div>
          <div>
            <div className="text-gray-500">Liquidation Bonus</div>
            <div className="text-white font-medium">5%</div>
          </div>
          <div>
            <div className="text-gray-500">Flash Loan Fee</div>
            <div className="text-white font-medium">0.09%</div>
          </div>
        </div>
      </div>
    </div>
  );
}
