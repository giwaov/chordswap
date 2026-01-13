import { useState, useEffect, useCallback } from 'react';
import { Contract, parseUnits, formatUnits } from 'ethers';
import { toast } from 'react-hot-toast';
import { CONTRACTS, ROUTER_ABI, ERC20_ABI, FACTORY_ABI, PAIR_ABI } from '../config';

interface SwapCardProps {
  wallet: {
    isConnected: boolean;
    address: string | null;
    signer: any;
    connect: () => void;
  };
}

const TOKENS = [
  { address: CONTRACTS.tokenA, symbol: 'ARCA', name: 'Arc Token A' },
  { address: CONTRACTS.tokenB, symbol: 'ARCB', name: 'Arc Token B' },
];

export default function SwapCard({ wallet }: SwapCardProps) {
  const [tokenInIndex, setTokenInIndex] = useState(0);
  const [tokenOutIndex, setTokenOutIndex] = useState(1);
  const [amountIn, setAmountIn] = useState('');
  const [amountOut, setAmountOut] = useState('');
  const [balanceIn, setBalanceIn] = useState('0');
  const [balanceOut, setBalanceOut] = useState('0');
  const [isLoading, setIsLoading] = useState(false);
  const [isFauceting, setIsFauceting] = useState(false);
  const [priceImpact, setPriceImpact] = useState<number>(0);
  const [reserves, setReserves] = useState<{ reserveIn: string; reserveOut: string } | null>(null);

  const tokenIn = TOKENS[tokenInIndex];
  const tokenOut = TOKENS[tokenOutIndex];

  // Fetch balances
  const fetchBalances = useCallback(async () => {
    if (!wallet.signer || !wallet.address) return;

    try {
      const tokenInContract = new Contract(tokenIn.address, ERC20_ABI, wallet.signer);
      const tokenOutContract = new Contract(tokenOut.address, ERC20_ABI, wallet.signer);
      
      const [balIn, balOut] = await Promise.all([
        tokenInContract.balanceOf(wallet.address),
        tokenOutContract.balanceOf(wallet.address),
      ]);
      
      setBalanceIn(formatUnits(balIn, 18));
      setBalanceOut(formatUnits(balOut, 18));
    } catch (error) {
      console.error('Failed to fetch balances:', error);
    }
  }, [wallet.signer, wallet.address, tokenIn.address, tokenOut.address]);

  useEffect(() => {
    if (wallet.isConnected) {
      fetchBalances();
      // Refresh balances every 10 seconds
      const interval = setInterval(fetchBalances, 10000);
      return () => clearInterval(interval);
    }
  }, [wallet.isConnected, fetchBalances]);

  // Get quote and calculate price impact
  useEffect(() => {
    if (!wallet.signer || !amountIn || parseFloat(amountIn) <= 0 || !CONTRACTS.router) {
      setAmountOut('');
      setPriceImpact(0);
      return;
    }

    const getQuote = async () => {
      try {
        const router = new Contract(CONTRACTS.router, ROUTER_ABI, wallet.signer);
        const factory = new Contract(CONTRACTS.factory, FACTORY_ABI, wallet.signer);
        
        const amountInWei = parseUnits(amountIn, 18);
        const quote = await router.getAmountOut(amountInWei, tokenIn.address, tokenOut.address);
        setAmountOut(formatUnits(quote, 18));

        // Calculate price impact
        const pairAddress = await factory.getPair(tokenIn.address, tokenOut.address);
        if (pairAddress && pairAddress !== '0x0000000000000000000000000000000000000000') {
          const pair = new Contract(pairAddress, PAIR_ABI, wallet.signer);
          const [reserve0, reserve1] = await pair.getReserves();
          const token0 = await pair.token0();
          
          const [reserveIn, reserveOut] = tokenIn.address.toLowerCase() === token0.toLowerCase()
            ? [reserve0, reserve1]
            : [reserve1, reserve0];
          
          setReserves({
            reserveIn: formatUnits(reserveIn, 18),
            reserveOut: formatUnits(reserveOut, 18)
          });

          // Price impact = (amount_in / reserve_in) * 100
          // More accurate: compare spot price vs execution price
          const spotPrice = Number(formatUnits(reserveOut, 18)) / Number(formatUnits(reserveIn, 18));
          const executionPrice = Number(formatUnits(quote, 18)) / Number(amountIn);
          const impact = ((spotPrice - executionPrice) / spotPrice) * 100;
          setPriceImpact(Math.max(0, impact));
        }
      } catch (error) {
        console.error('Failed to get quote:', error);
        setAmountOut('');
        setPriceImpact(0);
      }
    };

    const timer = setTimeout(getQuote, 500);
    return () => clearTimeout(timer);
  }, [wallet.signer, amountIn, tokenIn.address, tokenOut.address]);

  const handleFaucet = async (tokenAddress: string, tokenSymbol: string) => {
    if (!wallet.signer) return;

    setIsFauceting(true);
    try {
      toast.loading(`Getting ${tokenSymbol} from faucet...`, { id: 'faucet' });
      const tokenContract = new Contract(tokenAddress, ERC20_ABI, wallet.signer);
      const amount = parseUnits('1000', 18); // Get 1000 tokens
      const tx = await tokenContract.faucet(amount);
      await tx.wait();
      toast.success(`Got 1000 ${tokenSymbol}!`, { id: 'faucet' });
      fetchBalances();
    } catch (error: any) {
      console.error('Faucet failed:', error);
      toast.error(error.reason || 'Faucet failed', { id: 'faucet' });
    } finally {
      setIsFauceting(false);
    }
  };

  const handleSwap = async () => {
    if (!wallet.signer || !wallet.address || !amountIn) return;

    setIsLoading(true);

    try {
      const router = new Contract(CONTRACTS.router, ROUTER_ABI, wallet.signer);
      const tokenContract = new Contract(tokenIn.address, ERC20_ABI, wallet.signer);

      const amountInWei = parseUnits(amountIn, 18);
      const minAmountOut = parseUnits(
        (parseFloat(amountOut) * 0.995).toFixed(18),
        18
      );

      // Check allowance
      const allowance = await tokenContract.allowance(wallet.address, CONTRACTS.router);
      if (allowance < amountInWei) {
        toast.loading('Approving tokens...', { id: 'approve' });
        const approveTx = await tokenContract.approve(CONTRACTS.router, amountInWei);
        await approveTx.wait();
        toast.success('Tokens approved!', { id: 'approve' });
      }

      // Execute swap
      toast.loading('Swapping tokens...', { id: 'swap' });
      const deadline = Math.floor(Date.now() / 1000) + 300;
      const path = [tokenIn.address, tokenOut.address];

      const tx = await router.swapExactTokensForTokens(
        amountInWei,
        minAmountOut,
        path,
        wallet.address,
        deadline
      );

      await tx.wait();
      toast.success('Swap successful!', { id: 'swap' });

      setAmountIn('');
      setAmountOut('');
      fetchBalances();
    } catch (error: any) {
      console.error('Swap failed:', error);
      toast.error(error.reason || error.message || 'Swap failed', { id: 'swap' });
    } finally {
      setIsLoading(false);
    }
  };

  const switchTokens = () => {
    setTokenInIndex(tokenOutIndex);
    setTokenOutIndex(tokenInIndex);
    setAmountIn(amountOut);
    setAmountOut('');
  };

  const contractsConfigured = CONTRACTS.router && CONTRACTS.tokenA && CONTRACTS.tokenB;

  return (
    <div className="swap-card">
      <div className="flex justify-between items-center mb-6">
        <h2 className="text-xl font-semibold text-white">Swap</h2>
        {wallet.isConnected && (
          <button
            onClick={fetchBalances}
            className="text-gray-400 hover:text-white transition-colors"
            title="Refresh balances"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
          </button>
        )}
      </div>

      {!contractsConfigured ? (
        <div className="text-center py-8">
          <p className="text-gray-400 mb-4">Contracts not configured</p>
          <p className="text-sm text-gray-500">
            Deploy contracts and update addresses in{' '}
            <code className="text-arc-primary">frontend/src/config.ts</code>
          </p>
        </div>
      ) : (
        <>
          {/* From */}
          <div className="mb-2 p-4 bg-arc-darker rounded-xl">
            <div className="flex justify-between text-sm text-gray-400 mb-2">
              <span>From</span>
              <span className="flex items-center gap-2">
                Balance: {parseFloat(balanceIn).toFixed(4)} {tokenIn.symbol}
                {wallet.isConnected && parseFloat(balanceIn) < 100 && (
                  <button
                    onClick={() => handleFaucet(tokenIn.address, tokenIn.symbol)}
                    disabled={isFauceting}
                    className="text-xs bg-arc-primary/20 text-arc-primary px-2 py-0.5 rounded hover:bg-arc-primary/30 transition-colors"
                  >
                    {isFauceting ? '...' : 'Faucet'}
                  </button>
                )}
              </span>
            </div>
            <div className="flex gap-3 items-center">
              <input
                type="number"
                placeholder="0.0"
                value={amountIn}
                onChange={(e) => setAmountIn(e.target.value)}
                className="flex-1 bg-transparent text-white text-2xl font-medium focus:outline-none"
              />
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setAmountIn(balanceIn)}
                  className="px-2 py-1 text-arc-primary text-xs hover:bg-arc-primary/20 rounded transition-colors"
                >
                  MAX
                </button>
                <div className="px-3 py-2 bg-arc-dark rounded-lg text-white font-medium">
                  {tokenIn.symbol}
                </div>
              </div>
            </div>
          </div>

          {/* Switch Button */}
          <div className="flex justify-center -my-2 relative z-10">
            <button
              onClick={switchTokens}
              className="p-2 bg-arc-dark border-4 border-arc-darker rounded-xl hover:bg-arc-primary/20 transition-colors group"
            >
              <svg
                className="w-5 h-5 text-gray-400 group-hover:text-arc-primary transition-colors"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4" />
              </svg>
            </button>
          </div>

          {/* To */}
          <div className="mb-6 p-4 bg-arc-darker rounded-xl">
            <div className="flex justify-between text-sm text-gray-400 mb-2">
              <span>To (estimated)</span>
              <span className="flex items-center gap-2">
                Balance: {parseFloat(balanceOut).toFixed(4)} {tokenOut.symbol}
                {wallet.isConnected && parseFloat(balanceOut) < 100 && (
                  <button
                    onClick={() => handleFaucet(tokenOut.address, tokenOut.symbol)}
                    disabled={isFauceting}
                    className="text-xs bg-arc-primary/20 text-arc-primary px-2 py-0.5 rounded hover:bg-arc-primary/30 transition-colors"
                  >
                    {isFauceting ? '...' : 'Faucet'}
                  </button>
                )}
              </span>
            </div>
            <div className="flex gap-3 items-center">
              <input
                type="text"
                placeholder="0.0"
                value={amountOut}
                readOnly
                className="flex-1 bg-transparent text-white text-2xl font-medium focus:outline-none"
              />
              <div className="px-3 py-2 bg-arc-dark rounded-lg text-white font-medium">
                {tokenOut.symbol}
              </div>
            </div>
          </div>

          {/* Swap Info */}
          {amountIn && amountOut && parseFloat(amountIn) > 0 && (
            <div className="mb-4 p-3 bg-arc-darker rounded-xl text-sm">
              <div className="flex justify-between text-gray-400">
                <span>Rate</span>
                <span>1 {tokenIn.symbol} = {(parseFloat(amountOut) / parseFloat(amountIn)).toFixed(6)} {tokenOut.symbol}</span>
              </div>
              <div className="flex justify-between text-gray-400 mt-1">
                <span>Slippage Tolerance</span>
                <span>0.5%</span>
              </div>
              <div className="flex justify-between text-gray-400 mt-1">
                <span>Minimum Received</span>
                <span>{(parseFloat(amountOut) * 0.995).toFixed(6)} {tokenOut.symbol}</span>
              </div>
              <div className={`flex justify-between mt-1 ${priceImpact > 5 ? 'text-red-400' : priceImpact > 2 ? 'text-yellow-400' : 'text-gray-400'}`}>
                <span>Price Impact</span>
                <span>{priceImpact.toFixed(2)}%</span>
              </div>
              {reserves && (
                <div className="flex justify-between text-gray-500 mt-1 text-xs">
                  <span>Pool Liquidity</span>
                  <span>{parseFloat(reserves.reserveIn).toFixed(2)} / {parseFloat(reserves.reserveOut).toFixed(2)}</span>
                </div>
              )}
            </div>
          )}

          {/* Price Impact Warning */}
          {priceImpact > 5 && (
            <div className="mb-4 p-3 bg-red-500/20 border border-red-500/50 rounded-xl">
              <div className="flex items-center gap-2 text-red-400">
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
                <span className="font-semibold">High Price Impact!</span>
              </div>
              <p className="text-red-400/80 text-sm mt-1">
                This swap has a {priceImpact.toFixed(2)}% price impact. Consider swapping a smaller amount.
              </p>
            </div>
          )}

          {priceImpact > 2 && priceImpact <= 5 && (
            <div className="mb-4 p-3 bg-yellow-500/20 border border-yellow-500/50 rounded-xl">
              <div className="flex items-center gap-2 text-yellow-400">
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span className="font-medium">Moderate Price Impact</span>
              </div>
              <p className="text-yellow-400/80 text-sm mt-1">
                This swap has a {priceImpact.toFixed(2)}% price impact.
              </p>
            </div>
          )}

          {/* Action Button */}
          {!wallet.isConnected ? (
            <button onClick={wallet.connect} className="btn-primary">
              Connect Wallet
            </button>
          ) : parseFloat(balanceIn) <= 0 ? (
            <button
              onClick={() => handleFaucet(tokenIn.address, tokenIn.symbol)}
              disabled={isFauceting}
              className="btn-primary"
            >
              {isFauceting ? 'Getting tokens...' : `Get ${tokenIn.symbol} from Faucet`}
            </button>
          ) : (
            <button
              onClick={handleSwap}
              disabled={isLoading || !amountIn || !amountOut || parseFloat(amountIn) > parseFloat(balanceIn)}
              className="btn-primary"
            >
              {isLoading ? 'Swapping...' : parseFloat(amountIn) > parseFloat(balanceIn) ? 'Insufficient Balance' : 'Swap'}
            </button>
          )}
        </>
      )}
    </div>
  );
}
