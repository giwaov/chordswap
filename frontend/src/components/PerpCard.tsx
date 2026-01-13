import { useState, useEffect, useCallback } from 'react';
import { ethers } from 'ethers';
import { CONTRACTS, PERP_EXCHANGE_ABI, PRICE_ORACLE_ABI, ERC20_ABI } from '../config';

interface Position {
  size: bigint;
  collateral: bigint;
  entryPrice: bigint;
  isLong: boolean;
  unrealizedPnl: bigint;
  leverage: bigint;
  liquidationPrice: bigint;
  hasPosition: boolean;
}

interface FundingInfo {
  currentFundingRate: bigint;
  nextFundingTime: bigint;
  longOI: bigint;
  shortOI: bigint;
}

interface PerpCardProps {
  account: string;
  provider: ethers.BrowserProvider | null;
}

export default function PerpCard({ account, provider }: PerpCardProps) {
  const [isLong, setIsLong] = useState(true);
  const [collateralAmount, setCollateralAmount] = useState('');
  const [leverage, setLeverage] = useState(5);
  const [loading, setLoading] = useState(false);
  const [position, setPosition] = useState<Position | null>(null);
  const [fundingInfo, setFundingInfo] = useState<FundingInfo | null>(null);
  const [marketPrice, setMarketPrice] = useState<bigint>(BigInt(0));
  const [collateralBalance, setCollateralBalance] = useState<bigint>(BigInt(0));
  const [collateralSymbol, setCollateralSymbol] = useState('ARCA');

  const perpAddress = CONTRACTS.perpExchange;
  const marketToken = CONTRACTS.tokenB; // Trading ARCB

  const fetchData = useCallback(async () => {
    if (!provider || !account || !perpAddress) return;

    try {
      const perpContract = new ethers.Contract(perpAddress, PERP_EXCHANGE_ABI, provider);
      
      // Get collateral token
      const collateralAddr = await perpContract.collateralToken();
      const collateralContract = new ethers.Contract(collateralAddr, ERC20_ABI, provider);
      
      // Fetch balance and symbol
      const [balance, symbol] = await Promise.all([
        collateralContract.balanceOf(account),
        collateralContract.symbol()
      ]);
      setCollateralBalance(balance);
      setCollateralSymbol(symbol);

      // Get oracle and price
      const oracleAddr = await perpContract.priceOracle();
      const oracleContract = new ethers.Contract(oracleAddr, PRICE_ORACLE_ABI, provider);
      
      try {
        const price = await oracleContract.getPrice(marketToken);
        setMarketPrice(price);
      } catch {
        setMarketPrice(BigInt(0));
      }

      // Get position
      const pos = await perpContract.getPosition(account, marketToken);
      setPosition({
        size: pos[0],
        collateral: pos[1],
        entryPrice: pos[2],
        isLong: pos[3],
        unrealizedPnl: pos[4],
        leverage: pos[5],
        liquidationPrice: pos[6],
        hasPosition: pos[0] > BigInt(0)
      });

      // Get funding info
      const funding = await perpContract.getFundingInfo();
      setFundingInfo({
        currentFundingRate: funding[0],
        nextFundingTime: funding[1],
        longOI: funding[2],
        shortOI: funding[3]
      });
    } catch (error) {
      console.error('Error fetching perp data:', error);
    }
  }, [provider, account, perpAddress, marketToken]);

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 10000);
    return () => clearInterval(interval);
  }, [fetchData]);

  const openPosition = async () => {
    if (!provider || !perpAddress || !collateralAmount) return;

    try {
      setLoading(true);
      const signer = await provider.getSigner();
      const perpContract = new ethers.Contract(perpAddress, PERP_EXCHANGE_ABI, signer);
      
      // Get collateral token and approve
      const collateralAddr = await perpContract.collateralToken();
      const collateralContract = new ethers.Contract(collateralAddr, ERC20_ABI, signer);
      
      const amount = ethers.parseEther(collateralAmount);
      
      // Check allowance and approve if needed
      const allowance = await collateralContract.allowance(account, perpAddress);
      if (allowance < amount) {
        const approveTx = await collateralContract.approve(perpAddress, ethers.MaxUint256);
        await approveTx.wait();
      }
      
      // Open position
      const tx = await perpContract.openPosition(marketToken, amount, leverage, isLong);
      await tx.wait();
      
      setCollateralAmount('');
      fetchData();
    } catch (error: any) {
      console.error('Error opening position:', error);
      alert(error.reason || error.message || 'Transaction failed');
    } finally {
      setLoading(false);
    }
  };

  const closePosition = async () => {
    if (!provider || !perpAddress) return;

    try {
      setLoading(true);
      const signer = await provider.getSigner();
      const perpContract = new ethers.Contract(perpAddress, PERP_EXCHANGE_ABI, signer);
      
      const tx = await perpContract.closePosition(marketToken);
      await tx.wait();
      
      fetchData();
    } catch (error: any) {
      console.error('Error closing position:', error);
      alert(error.reason || error.message || 'Transaction failed');
    } finally {
      setLoading(false);
    }
  };

  const formatPrice = (price: bigint) => {
    if (price === BigInt(0)) return '$0.00';
    return '$' + Number(ethers.formatEther(price)).toFixed(4);
  };

  const formatPnL = (pnl: bigint) => {
    const value = Number(ethers.formatEther(pnl));
    const sign = value >= 0 ? '+' : '';
    return sign + value.toFixed(4);
  };

  const calculatePositionSize = () => {
    if (!collateralAmount || marketPrice === BigInt(0)) return '0';
    try {
      const collateral = ethers.parseEther(collateralAmount);
      const positionValue = collateral * BigInt(leverage);
      const size = (positionValue * BigInt(10**18)) / marketPrice;
      return Number(ethers.formatEther(size)).toFixed(4);
    } catch {
      return '0';
    }
  };

  // Check if perp exchange is deployed
  if (!perpAddress) {
    return (
      <div className="bg-gray-900 rounded-2xl p-6 shadow-xl border border-gray-800">
        <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
          ⚡ Perpetual Trading
        </h2>
        <div className="text-center py-8">
          <p className="text-gray-400 mb-4">Perpetual DEX not deployed yet.</p>
          <p className="text-gray-500 text-sm">
            Deploy the PerpExchange contract and update the config.ts file with the contract address.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-gray-900 rounded-2xl p-6 shadow-xl border border-gray-800">
      <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
        ⚡ Perpetual Trading
      </h2>

      {/* Market Info */}
      <div className="grid grid-cols-2 gap-4 mb-6">
        <div className="bg-gray-800 rounded-xl p-3">
          <p className="text-gray-400 text-xs">ARCB/USD</p>
          <p className="text-white font-bold text-lg">{formatPrice(marketPrice)}</p>
        </div>
        <div className="bg-gray-800 rounded-xl p-3">
          <p className="text-gray-400 text-xs">Funding Rate</p>
          <p className={`font-bold text-lg ${fundingInfo && fundingInfo.currentFundingRate >= 0 ? 'text-green-400' : 'text-red-400'}`}>
            {fundingInfo ? (Number(fundingInfo.currentFundingRate) / 1e14).toFixed(4) + '%' : '-'}
          </p>
        </div>
      </div>

      {/* Open Interest */}
      {fundingInfo && (
        <div className="bg-gray-800 rounded-xl p-3 mb-6">
          <p className="text-gray-400 text-xs mb-2">Open Interest</p>
          <div className="flex justify-between text-sm">
            <span className="text-green-400">
              Long: ${Number(ethers.formatEther(fundingInfo.longOI)).toLocaleString()}
            </span>
            <span className="text-red-400">
              Short: ${Number(ethers.formatEther(fundingInfo.shortOI)).toLocaleString()}
            </span>
          </div>
        </div>
      )}

      {/* Position Display */}
      {position?.hasPosition && (
        <div className="bg-gray-800 rounded-xl p-4 mb-6 border-l-4 border-blue-500">
          <div className="flex justify-between items-center mb-3">
            <span className="text-white font-semibold">Your Position</span>
            <span className={`px-2 py-1 rounded text-xs font-bold ${position.isLong ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
              {position.isLong ? 'LONG' : 'SHORT'} {Number(position.leverage)}x
            </span>
          </div>
          <div className="grid grid-cols-2 gap-3 text-sm">
            <div>
              <p className="text-gray-400">Size</p>
              <p className="text-white">{Number(ethers.formatEther(position.size)).toFixed(4)} ARCB</p>
            </div>
            <div>
              <p className="text-gray-400">Collateral</p>
              <p className="text-white">{Number(ethers.formatEther(position.collateral)).toFixed(4)} {collateralSymbol}</p>
            </div>
            <div>
              <p className="text-gray-400">Entry Price</p>
              <p className="text-white">{formatPrice(position.entryPrice)}</p>
            </div>
            <div>
              <p className="text-gray-400">Liq. Price</p>
              <p className="text-orange-400">{formatPrice(position.liquidationPrice)}</p>
            </div>
            <div className="col-span-2">
              <p className="text-gray-400">Unrealized PnL</p>
              <p className={`text-lg font-bold ${Number(position.unrealizedPnl) >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                {formatPnL(position.unrealizedPnl)} {collateralSymbol}
              </p>
            </div>
          </div>
          <button
            onClick={closePosition}
            disabled={loading}
            className="w-full mt-4 bg-red-500 hover:bg-red-600 text-white font-bold py-2 rounded-xl transition-colors disabled:opacity-50"
          >
            {loading ? 'Closing...' : 'Close Position'}
          </button>
        </div>
      )}

      {/* Open Position Form */}
      {!position?.hasPosition && (
        <>
          {/* Long/Short Toggle */}
          <div className="flex gap-2 mb-4">
            <button
              onClick={() => setIsLong(true)}
              className={`flex-1 py-3 rounded-xl font-bold transition-colors ${
                isLong 
                  ? 'bg-green-500 text-white' 
                  : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
              }`}
            >
              Long
            </button>
            <button
              onClick={() => setIsLong(false)}
              className={`flex-1 py-3 rounded-xl font-bold transition-colors ${
                !isLong 
                  ? 'bg-red-500 text-white' 
                  : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
              }`}
            >
              Short
            </button>
          </div>

          {/* Collateral Input */}
          <div className="bg-gray-800 rounded-xl p-4 mb-4">
            <div className="flex justify-between mb-2">
              <span className="text-gray-400 text-sm">Collateral</span>
              <span className="text-gray-400 text-sm">
                Balance: {Number(ethers.formatEther(collateralBalance)).toFixed(4)} {collateralSymbol}
              </span>
            </div>
            <div className="flex gap-2">
              <input
                type="number"
                value={collateralAmount}
                onChange={(e) => setCollateralAmount(e.target.value)}
                placeholder="0.0"
                className="flex-1 bg-transparent text-white text-2xl font-bold outline-none"
              />
              <button
                onClick={() => setCollateralAmount(ethers.formatEther(collateralBalance))}
                className="text-blue-400 text-sm hover:text-blue-300"
              >
                MAX
              </button>
            </div>
          </div>

          {/* Leverage Slider */}
          <div className="bg-gray-800 rounded-xl p-4 mb-4">
            <div className="flex justify-between mb-2">
              <span className="text-gray-400 text-sm">Leverage</span>
              <span className="text-white font-bold">{leverage}x</span>
            </div>
            <input
              type="range"
              min="1"
              max="50"
              value={leverage}
              onChange={(e) => setLeverage(Number(e.target.value))}
              className="w-full accent-blue-500"
            />
            <div className="flex justify-between text-xs text-gray-500 mt-1">
              <span>1x</span>
              <span>10x</span>
              <span>25x</span>
              <span>50x</span>
            </div>
          </div>

          {/* Position Info Preview */}
          {collateralAmount && (
            <div className="bg-gray-800 rounded-xl p-4 mb-4">
              <p className="text-gray-400 text-sm mb-2">Position Size</p>
              <p className="text-white font-bold text-lg">{calculatePositionSize()} ARCB</p>
              <p className="text-gray-400 text-xs mt-1">
                Value: ${(Number(collateralAmount) * leverage).toFixed(2)}
              </p>
            </div>
          )}

          {/* Open Position Button */}
          <button
            onClick={openPosition}
            disabled={loading || !collateralAmount || !account}
            className={`w-full py-4 rounded-xl font-bold text-white transition-colors disabled:opacity-50 ${
              isLong 
                ? 'bg-green-500 hover:bg-green-600' 
                : 'bg-red-500 hover:bg-red-600'
            }`}
          >
            {loading ? 'Opening...' : `Open ${isLong ? 'Long' : 'Short'} Position`}
          </button>
        </>
      )}

      {/* Info Footer */}
      <div className="mt-4 text-center">
        <p className="text-gray-500 text-xs">
          Trading Fee: 0.1% • Max Leverage: 50x
        </p>
      </div>
    </div>
  );
}
