import { useState, useEffect } from 'react';
import { Contract, parseUnits, formatUnits } from 'ethers';
import { CONTRACTS, ROUTER_ABI, ERC20_ABI } from '../config';
import { useWallet } from './useWallet';

export function useSwap() {
  const { signer, address } = useWallet();
  const [tokenIn, setTokenIn] = useState(CONTRACTS.tokenA);
  const [tokenOut, setTokenOut] = useState(CONTRACTS.tokenB);
  const [amountIn, setAmountIn] = useState('');
  const [amountOut, setAmountOut] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [balance, setBalance] = useState('0');

  // Fetch balance
  useEffect(() => {
    if (!signer || !address || !tokenIn) return;

    const fetchBalance = async () => {
      try {
        const tokenContract = new Contract(tokenIn, ERC20_ABI, signer);
        const bal = await tokenContract.balanceOf(address);
        setBalance(formatUnits(bal, 18));
      } catch (error) {
        console.error('Failed to fetch balance:', error);
      }
    };

    fetchBalance();
  }, [signer, address, tokenIn]);

  // Get quote when input changes
  useEffect(() => {
    if (!signer || !amountIn || parseFloat(amountIn) <= 0) {
      setAmountOut('');
      return;
    }

    const getQuote = async () => {
      try {
        const router = new Contract(CONTRACTS.router, ROUTER_ABI, signer);
        const amountInWei = parseUnits(amountIn, 18);
        const quote = await router.getAmountOut(amountInWei, tokenIn, tokenOut);
        setAmountOut(formatUnits(quote, 18));
      } catch (error) {
        console.error('Failed to get quote:', error);
        setAmountOut('');
      }
    };

    const timer = setTimeout(getQuote, 500);
    return () => clearTimeout(timer);
  }, [signer, amountIn, tokenIn, tokenOut]);

  const swap = async () => {
    if (!signer || !address || !amountIn) return;

    setIsLoading(true);

    try {
      const router = new Contract(CONTRACTS.router, ROUTER_ABI, signer);
      const tokenContract = new Contract(tokenIn, ERC20_ABI, signer);

      const amountInWei = parseUnits(amountIn, 18);
      const minAmountOut = parseUnits(
        (parseFloat(amountOut) * 0.995).toFixed(18), // 0.5% slippage
        18
      );

      // Check allowance and approve if needed
      const allowance = await tokenContract.allowance(address, CONTRACTS.router);
      if (allowance < amountInWei) {
        const approveTx = await tokenContract.approve(CONTRACTS.router, amountInWei);
        await approveTx.wait();
      }

      // Execute swap
      const deadline = Math.floor(Date.now() / 1000) + 300; // 5 minutes
      const path = [tokenIn, tokenOut];

      const tx = await router.swapExactTokensForTokens(
        amountInWei,
        minAmountOut,
        path,
        address,
        deadline
      );

      await tx.wait();
      
      // Reset
      setAmountIn('');
      setAmountOut('');
      
      return tx.hash;
    } catch (error) {
      console.error('Swap failed:', error);
      throw error;
    } finally {
      setIsLoading(false);
    }
  };

  const switchTokens = () => {
    setTokenIn(tokenOut);
    setTokenOut(tokenIn);
    setAmountIn(amountOut);
    setAmountOut('');
  };

  return {
    tokenIn,
    tokenOut,
    amountIn,
    amountOut,
    balance,
    isLoading,
    setTokenIn,
    setTokenOut,
    setAmountIn,
    swap,
    switchTokens,
  };
}
