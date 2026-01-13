import { useState, useEffect, useCallback } from 'react';
import { ethers } from 'ethers';
import { CONTRACTS, LENDING_POOL_ABI, ERC20_ABI, LENDING_TOKENS, PRICE_ORACLE_ABI } from '../config';

export interface MarketData {
  address: string;
  symbol: string;
  name: string;
  decimals: number;
  icon: string;
  color: string;
  // Market stats
  totalSupply: string;
  totalBorrows: string;
  availableLiquidity: string;
  supplyAPR: string;
  borrowAPR: string;
  utilization: string;
  collateralFactor: string;
  liquidationThreshold: string;
  // User data
  walletBalance: string;
  suppliedBalance: string;
  borrowedBalance: string;
  isCollateralEnabled: boolean;
  // Price
  price: string;
}

export interface UserAccountData {
  totalCollateralValue: string;
  totalBorrowValue: string;
  availableBorrowValue: string;
  healthFactor: string;
  netAPY: string;
}

export function useLending(provider: ethers.BrowserProvider | null, address: string | null) {
  const [markets, setMarkets] = useState<MarketData[]>([]);
  const [userAccount, setUserAccount] = useState<UserAccountData | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load market data
  const loadMarketData = useCallback(async () => {
    if (!provider) return;
    
    setLoading(true);
    setError(null);

    try {
      const lendingPool = new ethers.Contract(
        CONTRACTS.lendingPool,
        LENDING_POOL_ABI,
        provider
      );

      const oracle = new ethers.Contract(
        CONTRACTS.lendingOracle,
        PRICE_ORACLE_ABI,
        provider
      );

      const marketsData: MarketData[] = [];

      for (const token of LENDING_TOKENS) {
        try {
          // Get market info
          const marketInfo = await lendingPool.getMarketInfo(token.address);
          const rates = await lendingPool.getMarketRates(token.address);
          const price = await oracle.getPrice(token.address);

          // Get user balances if connected
          let walletBalance = '0';
          let suppliedBalance = '0';
          let borrowedBalance = '0';
          let isCollateralEnabled = false;

          if (address) {
            const tokenContract = new ethers.Contract(token.address, ERC20_ABI, provider);
            walletBalance = ethers.formatUnits(
              await tokenContract.balanceOf(address),
              token.decimals
            );
            suppliedBalance = ethers.formatUnits(
              await lendingPool.userAssetBalance(address, token.address),
              token.decimals
            );
            borrowedBalance = ethers.formatUnits(
              await lendingPool.borrowBalance(address, token.address),
              token.decimals
            );
            isCollateralEnabled = await lendingPool.userCollateral(address, token.address);
          }

          const totalSupply = ethers.formatUnits(marketInfo[1], token.decimals);
          const totalBorrows = ethers.formatUnits(marketInfo[2], token.decimals);
          const available = parseFloat(totalSupply) - parseFloat(totalBorrows);

          marketsData.push({
            address: token.address,
            symbol: token.symbol,
            name: token.name,
            decimals: token.decimals,
            icon: token.icon,
            color: token.color,
            totalSupply,
            totalBorrows,
            availableLiquidity: available.toFixed(2),
            supplyAPR: (parseFloat(ethers.formatUnits(rates[0], 18)) * 100).toFixed(2),
            borrowAPR: (parseFloat(ethers.formatUnits(rates[1], 18)) * 100).toFixed(2),
            utilization: (parseFloat(ethers.formatUnits(rates[2], 18)) * 100).toFixed(2),
            collateralFactor: (parseFloat(ethers.formatUnits(marketInfo[4], 18)) * 100).toFixed(0),
            liquidationThreshold: (parseFloat(ethers.formatUnits(marketInfo[5], 18)) * 100).toFixed(0),
            walletBalance,
            suppliedBalance,
            borrowedBalance,
            isCollateralEnabled,
            price: ethers.formatUnits(price, 18),
          });
        } catch (err) {
          console.error(`Error loading market ${token.symbol}:`, err);
        }
      }

      setMarkets(marketsData);

      // Load user account data
      if (address) {
        try {
          const accountData = await lendingPool.getUserAccountData(address);
          const healthFactor = await lendingPool.healthFactor(address);

          // Calculate net APY
          let totalSupplyValue = 0;
          let totalBorrowValue = 0;
          let weightedSupplyAPR = 0;
          let weightedBorrowAPR = 0;

          for (const market of marketsData) {
            const supplyValue = parseFloat(market.suppliedBalance) * parseFloat(market.price);
            const borrowValue = parseFloat(market.borrowedBalance) * parseFloat(market.price);
            totalSupplyValue += supplyValue;
            totalBorrowValue += borrowValue;
            weightedSupplyAPR += supplyValue * parseFloat(market.supplyAPR);
            weightedBorrowAPR += borrowValue * parseFloat(market.borrowAPR);
          }

          const avgSupplyAPR = totalSupplyValue > 0 ? weightedSupplyAPR / totalSupplyValue : 0;
          const avgBorrowAPR = totalBorrowValue > 0 ? weightedBorrowAPR / totalBorrowValue : 0;
          const netAPY = totalSupplyValue > 0 
            ? ((avgSupplyAPR * totalSupplyValue - avgBorrowAPR * totalBorrowValue) / totalSupplyValue)
            : 0;

          setUserAccount({
            totalCollateralValue: ethers.formatUnits(accountData[0], 18),
            totalBorrowValue: ethers.formatUnits(accountData[1], 18),
            availableBorrowValue: ethers.formatUnits(accountData[2], 18),
            healthFactor: parseFloat(ethers.formatUnits(healthFactor, 18)) > 1000 
              ? '∞' 
              : parseFloat(ethers.formatUnits(healthFactor, 18)).toFixed(2),
            netAPY: netAPY.toFixed(2),
          });
        } catch (err) {
          console.error('Error loading user account:', err);
        }
      }
    } catch (err) {
      console.error('Error loading lending data:', err);
      setError('Failed to load lending data');
    } finally {
      setLoading(false);
    }
  }, [provider, address]);

  // Supply
  const supply = useCallback(async (asset: string, amount: string, decimals: number) => {
    if (!provider || !address) throw new Error('Wallet not connected');

    const signer = await provider.getSigner();
    const tokenContract = new ethers.Contract(asset, ERC20_ABI, signer);
    const lendingPool = new ethers.Contract(CONTRACTS.lendingPool, LENDING_POOL_ABI, signer);

    const amountWei = ethers.parseUnits(amount, decimals);

    // Approve
    const allowance = await tokenContract.allowance(address, CONTRACTS.lendingPool);
    if (allowance < amountWei) {
      const approveTx = await tokenContract.approve(CONTRACTS.lendingPool, ethers.MaxUint256);
      await approveTx.wait();
    }

    // Supply
    const tx = await lendingPool.supply(asset, amountWei);
    await tx.wait();

    await loadMarketData();
    return tx;
  }, [provider, address, loadMarketData]);

  // Withdraw
  const withdraw = useCallback(async (asset: string, amount: string, decimals: number, max: boolean = false) => {
    if (!provider || !address) throw new Error('Wallet not connected');

    const signer = await provider.getSigner();
    const lendingPool = new ethers.Contract(CONTRACTS.lendingPool, LENDING_POOL_ABI, signer);

    const amountWei = max ? ethers.MaxUint256 : ethers.parseUnits(amount, decimals);

    const tx = await lendingPool.withdraw(asset, amountWei);
    await tx.wait();

    await loadMarketData();
    return tx;
  }, [provider, address, loadMarketData]);

  // Borrow
  const borrow = useCallback(async (asset: string, amount: string, decimals: number) => {
    if (!provider || !address) throw new Error('Wallet not connected');

    const signer = await provider.getSigner();
    const lendingPool = new ethers.Contract(CONTRACTS.lendingPool, LENDING_POOL_ABI, signer);

    const amountWei = ethers.parseUnits(amount, decimals);

    const tx = await lendingPool.borrow(asset, amountWei);
    await tx.wait();

    await loadMarketData();
    return tx;
  }, [provider, address, loadMarketData]);

  // Repay
  const repay = useCallback(async (asset: string, amount: string, decimals: number, max: boolean = false) => {
    if (!provider || !address) throw new Error('Wallet not connected');

    const signer = await provider.getSigner();
    const tokenContract = new ethers.Contract(asset, ERC20_ABI, signer);
    const lendingPool = new ethers.Contract(CONTRACTS.lendingPool, LENDING_POOL_ABI, signer);

    const amountWei = max ? ethers.MaxUint256 : ethers.parseUnits(amount, decimals);

    // Approve
    if (!max) {
      const allowance = await tokenContract.allowance(address, CONTRACTS.lendingPool);
      if (allowance < amountWei) {
        const approveTx = await tokenContract.approve(CONTRACTS.lendingPool, ethers.MaxUint256);
        await approveTx.wait();
      }
    }

    const tx = await lendingPool.repay(asset, amountWei);
    await tx.wait();

    await loadMarketData();
    return tx;
  }, [provider, address, loadMarketData]);

  // Enable/Disable Collateral
  const toggleCollateral = useCallback(async (asset: string, enable: boolean) => {
    if (!provider || !address) throw new Error('Wallet not connected');

    const signer = await provider.getSigner();
    const lendingPool = new ethers.Contract(CONTRACTS.lendingPool, LENDING_POOL_ABI, signer);

    const tx = enable 
      ? await lendingPool.enableCollateral(asset)
      : await lendingPool.disableCollateral(asset);
    await tx.wait();

    await loadMarketData();
    return tx;
  }, [provider, address, loadMarketData]);

  // Mint test tokens (faucet)
  const mintTestTokens = useCallback(async (asset: string, decimals: number) => {
    if (!provider || !address) throw new Error('Wallet not connected');

    const signer = await provider.getSigner();
    const tokenContract = new ethers.Contract(asset, ERC20_ABI, signer);

    // Mint different amounts based on token
    let amount;
    if (decimals === 6) amount = ethers.parseUnits('10000', 6); // 10k USDC
    else if (decimals === 8) amount = ethers.parseUnits('1', 8); // 1 WBTC
    else amount = ethers.parseUnits('10', 18); // 10 WETH

    const tx = await tokenContract.mint(address, amount);
    await tx.wait();

    await loadMarketData();
    return tx;
  }, [provider, address, loadMarketData]);

  // Load data on mount and when address changes
  useEffect(() => {
    loadMarketData();
  }, [loadMarketData]);

  // Auto refresh every 30 seconds
  useEffect(() => {
    const interval = setInterval(loadMarketData, 30000);
    return () => clearInterval(interval);
  }, [loadMarketData]);

  return {
    markets,
    userAccount,
    loading,
    error,
    refresh: loadMarketData,
    supply,
    withdraw,
    borrow,
    repay,
    toggleCollateral,
    mintTestTokens,
  };
}
