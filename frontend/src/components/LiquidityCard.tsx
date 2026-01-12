import { useState, useEffect } from 'react';
import { Contract, parseUnits, formatUnits } from 'ethers';
import { toast } from 'react-hot-toast';
import { CONTRACTS, ROUTER_ABI, ERC20_ABI, PAIR_ABI } from '../config';

interface LiquidityCardProps {
  wallet: {
    isConnected: boolean;
    address: string | null;
    signer: any;
    connect: () => void;
  };
}

export default function LiquidityCard({ wallet }: LiquidityCardProps) {
  const [mode, setMode] = useState<'add' | 'remove'>('add');
  const [amountA, setAmountA] = useState('');
  const [amountB, setAmountB] = useState('');
  const [lpAmount, setLpAmount] = useState('');
  const [balanceA, setBalanceA] = useState('0');
  const [balanceB, setBalanceB] = useState('0');
  const [lpBalance, setLpBalance] = useState('0');
  const [poolInfo, setPoolInfo] = useState({ reserveA: '0', reserveB: '0', totalSupply: '0' });
  const [isLoading, setIsLoading] = useState(false);

  // Fetch balances and pool info
  useEffect(() => {
    if (!wallet.signer || !wallet.address || !CONTRACTS.router) return;

    const fetchData = async () => {
      try {
        const tokenAContract = new Contract(CONTRACTS.tokenA, ERC20_ABI, wallet.signer);
        const tokenBContract = new Contract(CONTRACTS.tokenB, ERC20_ABI, wallet.signer);
        const router = new Contract(CONTRACTS.router, ROUTER_ABI, wallet.signer);

        const [balA, balB, pairInfo] = await Promise.all([
          tokenAContract.balanceOf(wallet.address),
          tokenBContract.balanceOf(wallet.address),
          router.getPairInfo(CONTRACTS.tokenA, CONTRACTS.tokenB).catch(() => null),
        ]);

        setBalanceA(formatUnits(balA, 18));
        setBalanceB(formatUnits(balB, 18));

        if (pairInfo && pairInfo[0] !== '0x0000000000000000000000000000000000000000') {
          const pairContract = new Contract(pairInfo[0], PAIR_ABI, wallet.signer);
          const lpBal = await pairContract.balanceOf(wallet.address);
          setLpBalance(formatUnits(lpBal, 18));
          setPoolInfo({
            reserveA: formatUnits(pairInfo[1], 18),
            reserveB: formatUnits(pairInfo[2], 18),
            totalSupply: formatUnits(pairInfo[3], 18),
          });
        }
      } catch (error) {
        console.error('Failed to fetch data:', error);
      }
    };

    fetchData();
  }, [wallet.signer, wallet.address]);

  // Auto-calculate pair amount
  useEffect(() => {
    if (!amountA || parseFloat(amountA) <= 0 || parseFloat(poolInfo.reserveA) <= 0) {
      return;
    }

    const ratioB = (parseFloat(amountA) * parseFloat(poolInfo.reserveB)) / parseFloat(poolInfo.reserveA);
    setAmountB(ratioB.toFixed(6));
  }, [amountA, poolInfo]);

  const handleAddLiquidity = async () => {
    if (!wallet.signer || !wallet.address || !amountA || !amountB) return;

    setIsLoading(true);

    try {
      const router = new Contract(CONTRACTS.router, ROUTER_ABI, wallet.signer);
      const tokenAContract = new Contract(CONTRACTS.tokenA, ERC20_ABI, wallet.signer);
      const tokenBContract = new Contract(CONTRACTS.tokenB, ERC20_ABI, wallet.signer);

      const amountAWei = parseUnits(amountA, 18);
      const amountBWei = parseUnits(amountB, 18);

      // Approve tokens
      toast.loading('Approving Token A...', { id: 'approveA' });
      const allowanceA = await tokenAContract.allowance(wallet.address, CONTRACTS.router);
      if (allowanceA < amountAWei) {
        const txA = await tokenAContract.approve(CONTRACTS.router, amountAWei);
        await txA.wait();
      }
      toast.success('Token A approved!', { id: 'approveA' });

      toast.loading('Approving Token B...', { id: 'approveB' });
      const allowanceB = await tokenBContract.allowance(wallet.address, CONTRACTS.router);
      if (allowanceB < amountBWei) {
        const txB = await tokenBContract.approve(CONTRACTS.router, amountBWei);
        await txB.wait();
      }
      toast.success('Token B approved!', { id: 'approveB' });

      // Add liquidity
      toast.loading('Adding liquidity...', { id: 'liquidity' });
      const deadline = Math.floor(Date.now() / 1000) + 300;

      const tx = await router.addLiquidity(
        CONTRACTS.tokenA,
        CONTRACTS.tokenB,
        amountAWei,
        amountBWei,
        0, // min A
        0, // min B
        wallet.address,
        deadline
      );

      await tx.wait();
      toast.success('Liquidity added!', { id: 'liquidity' });

      setAmountA('');
      setAmountB('');
    } catch (error: any) {
      console.error('Add liquidity failed:', error);
      toast.error(error.message || 'Failed to add liquidity', { id: 'liquidity' });
    } finally {
      setIsLoading(false);
    }
  };

  const handleRemoveLiquidity = async () => {
    if (!wallet.signer || !wallet.address || !lpAmount) return;

    setIsLoading(true);

    try {
      const router = new Contract(CONTRACTS.router, ROUTER_ABI, wallet.signer);
      const lpAmountWei = parseUnits(lpAmount, 18);

      // Get pair address and approve
      const pairInfo = await router.getPairInfo(CONTRACTS.tokenA, CONTRACTS.tokenB);
      const pairContract = new Contract(pairInfo[0], PAIR_ABI, wallet.signer);

      toast.loading('Approving LP tokens...', { id: 'approveLP' });
      const txApprove = await pairContract.approve(CONTRACTS.router, lpAmountWei);
      await txApprove.wait();
      toast.success('LP tokens approved!', { id: 'approveLP' });

      // Remove liquidity
      toast.loading('Removing liquidity...', { id: 'remove' });
      const deadline = Math.floor(Date.now() / 1000) + 300;

      const tx = await router.removeLiquidity(
        CONTRACTS.tokenA,
        CONTRACTS.tokenB,
        lpAmountWei,
        0,
        0,
        wallet.address,
        deadline
      );

      await tx.wait();
      toast.success('Liquidity removed!', { id: 'remove' });

      setLpAmount('');
    } catch (error: any) {
      console.error('Remove liquidity failed:', error);
      toast.error(error.message || 'Failed to remove liquidity', { id: 'remove' });
    } finally {
      setIsLoading(false);
    }
  };

  const contractsConfigured = CONTRACTS.router && CONTRACTS.tokenA && CONTRACTS.tokenB;

  return (
    <div className="swap-card">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-semibold text-white">Liquidity</h2>
        <div className="flex gap-2">
          <button
            onClick={() => setMode('add')}
            className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors ${
              mode === 'add' ? 'bg-arc-primary text-white' : 'text-gray-400 hover:text-white'
            }`}
          >
            Add
          </button>
          <button
            onClick={() => setMode('remove')}
            className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors ${
              mode === 'remove' ? 'bg-arc-primary text-white' : 'text-gray-400 hover:text-white'
            }`}
          >
            Remove
          </button>
        </div>
      </div>

      {!contractsConfigured ? (
        <div className="text-center py-8">
          <p className="text-gray-400 mb-4">Contracts not configured</p>
          <p className="text-sm text-gray-500">
            Deploy contracts and update addresses in{' '}
            <code className="text-arc-primary">frontend/src/config.ts</code>
          </p>
        </div>
      ) : mode === 'add' ? (
        <>
          {/* Token A */}
          <div className="mb-4">
            <div className="flex justify-between text-sm text-gray-400 mb-2">
              <span>Token A</span>
              <span>Balance: {parseFloat(balanceA).toFixed(4)}</span>
            </div>
            <input
              type="number"
              placeholder="0.0"
              value={amountA}
              onChange={(e) => setAmountA(e.target.value)}
              className="token-input"
            />
          </div>

          {/* Token B */}
          <div className="mb-6">
            <div className="flex justify-between text-sm text-gray-400 mb-2">
              <span>Token B</span>
              <span>Balance: {parseFloat(balanceB).toFixed(4)}</span>
            </div>
            <input
              type="number"
              placeholder="0.0"
              value={amountB}
              onChange={(e) => setAmountB(e.target.value)}
              className="token-input"
            />
          </div>

          {/* Pool Info */}
          {parseFloat(poolInfo.totalSupply) > 0 && (
            <div className="mb-4 p-3 bg-arc-darker rounded-xl text-sm">
              <div className="flex justify-between text-gray-400 mb-1">
                <span>Pool Reserve A</span>
                <span>{parseFloat(poolInfo.reserveA).toFixed(4)}</span>
              </div>
              <div className="flex justify-between text-gray-400 mb-1">
                <span>Pool Reserve B</span>
                <span>{parseFloat(poolInfo.reserveB).toFixed(4)}</span>
              </div>
              <div className="flex justify-between text-gray-400">
                <span>Your LP Tokens</span>
                <span>{parseFloat(lpBalance).toFixed(4)}</span>
              </div>
            </div>
          )}

          {!wallet.isConnected ? (
            <button onClick={wallet.connect} className="btn-primary">
              Connect Wallet
            </button>
          ) : (
            <button
              onClick={handleAddLiquidity}
              disabled={isLoading || !amountA || !amountB}
              className="btn-primary"
            >
              {isLoading ? 'Adding...' : 'Add Liquidity'}
            </button>
          )}
        </>
      ) : (
        <>
          {/* LP Amount */}
          <div className="mb-6">
            <div className="flex justify-between text-sm text-gray-400 mb-2">
              <span>LP Tokens to Remove</span>
              <span>Balance: {parseFloat(lpBalance).toFixed(4)}</span>
            </div>
            <div className="flex gap-3">
              <input
                type="number"
                placeholder="0.0"
                value={lpAmount}
                onChange={(e) => setLpAmount(e.target.value)}
                className="token-input flex-1"
              />
              <button
                onClick={() => setLpAmount(lpBalance)}
                className="px-3 py-2 bg-arc-primary/20 text-arc-primary rounded-lg text-sm hover:bg-arc-primary/30 transition-colors"
              >
                MAX
              </button>
            </div>
          </div>

          {!wallet.isConnected ? (
            <button onClick={wallet.connect} className="btn-primary">
              Connect Wallet
            </button>
          ) : (
            <button
              onClick={handleRemoveLiquidity}
              disabled={isLoading || !lpAmount}
              className="btn-primary"
            >
              {isLoading ? 'Removing...' : 'Remove Liquidity'}
            </button>
          )}
        </>
      )}
    </div>
  );
}
