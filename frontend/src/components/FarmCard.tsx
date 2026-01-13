import { useState, useEffect, useCallback } from 'react';
import { Contract, parseUnits, formatUnits } from 'ethers';
import { toast } from 'react-hot-toast';
import { CONTRACTS, PAIR_ABI, LP_FARM_ABI, ERC20_ABI } from '../config';

interface FarmCardProps {
  wallet: {
    isConnected: boolean;
    address: string | null;
    signer: any;
    connect: () => void;
  };
}

interface PoolInfo {
  pid: number;
  lpToken: string;
  allocPoint: number;
  totalStaked: string;
  depositFee: number;
  userStaked: string;
  pendingRewards: string;
  lpBalance: string;
  apy: number;
}

export default function FarmCard({ wallet }: FarmCardProps) {
  const [pools, setPools] = useState<PoolInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [stakeAmount, setStakeAmount] = useState('');
  const [unstakeAmount, setUnstakeAmount] = useState('');
  const [selectedPool, setSelectedPool] = useState<number | null>(null);
  const [actionLoading, setActionLoading] = useState(false);
  const [chordBalance, setChordBalance] = useState('0');

  const farmAddress = CONTRACTS.lpFarm;
  const chordTokenAddress = CONTRACTS.chordToken;

  const fetchPools = useCallback(async () => {
    if (!wallet.signer || !farmAddress) return;

    try {
      setLoading(true);
      const farm = new Contract(farmAddress, LP_FARM_ABI, wallet.signer);
      const poolLength = await farm.poolLength();
      
      const fetchedPools: PoolInfo[] = [];
      const rewardPerSecond = await farm.rewardPerSecond();
      const totalAllocPoint = await farm.totalAllocPoint();

      for (let pid = 0; pid < poolLength; pid++) {
        const [poolInfo, userInfo] = await Promise.all([
          farm.getPoolInfo(pid),
          wallet.address ? farm.getUserInfo(pid, wallet.address) : null,
        ]);

        let lpBalance = '0';
        if (wallet.address) {
          const lpToken = new Contract(poolInfo.lpToken, PAIR_ABI, wallet.signer);
          lpBalance = formatUnits(await lpToken.balanceOf(wallet.address), 18);
        }

        // Calculate APY
        const totalStakedNum = parseFloat(formatUnits(poolInfo.totalStaked, 18));
        const rewardPerYear = parseFloat(formatUnits(rewardPerSecond, 18)) * 365 * 24 * 3600;
        const poolRewardPerYear = (rewardPerYear * Number(poolInfo.allocPoint)) / Number(totalAllocPoint);
        const apy = totalStakedNum > 0 ? (poolRewardPerYear / totalStakedNum) * 100 : 0;

        fetchedPools.push({
          pid,
          lpToken: poolInfo.lpToken,
          allocPoint: Number(poolInfo.allocPoint),
          totalStaked: formatUnits(poolInfo.totalStaked, 18),
          depositFee: Number(poolInfo.depositFee) / 100,
          userStaked: userInfo ? formatUnits(userInfo.amount, 18) : '0',
          pendingRewards: userInfo ? formatUnits(userInfo.pending, 18) : '0',
          lpBalance,
          apy,
        });
      }

      setPools(fetchedPools);

      // Fetch CHORD balance
      if (wallet.address && chordTokenAddress) {
        const chord = new Contract(chordTokenAddress, ERC20_ABI, wallet.signer);
        const balance = await chord.balanceOf(wallet.address);
        setChordBalance(formatUnits(balance, 18));
      }
    } catch (error) {
      console.error('Failed to fetch pools:', error);
    } finally {
      setLoading(false);
    }
  }, [wallet.signer, wallet.address, farmAddress, chordTokenAddress]);

  useEffect(() => {
    if (wallet.isConnected) {
      fetchPools();
      const interval = setInterval(fetchPools, 30000);
      return () => clearInterval(interval);
    }
  }, [wallet.isConnected, fetchPools]);

  const handleStake = async (pid: number) => {
    if (!wallet.signer || !wallet.address || !farmAddress || !stakeAmount) return;

    setActionLoading(true);
    try {
      const pool = pools.find(p => p.pid === pid);
      if (!pool) return;

      const lpToken = new Contract(pool.lpToken, PAIR_ABI, wallet.signer);
      const farm = new Contract(farmAddress, LP_FARM_ABI, wallet.signer);
      const amount = parseUnits(stakeAmount, 18);

      // Approve
      toast.loading('Approving LP tokens...', { id: 'approve' });
      const allowance = await lpToken.allowance(wallet.address, farmAddress);
      if (allowance < amount) {
        const approveTx = await lpToken.approve(farmAddress, amount);
        await approveTx.wait();
      }
      toast.success('Approved!', { id: 'approve' });

      // Stake
      toast.loading('Staking LP tokens...', { id: 'stake' });
      const tx = await farm.deposit(pid, amount);
      await tx.wait();
      toast.success('Staked successfully!', { id: 'stake' });

      setStakeAmount('');
      setSelectedPool(null);
      fetchPools();
    } catch (error: any) {
      console.error('Failed to stake:', error);
      toast.error(error.reason || 'Failed to stake', { id: 'stake' });
    } finally {
      setActionLoading(false);
    }
  };

  const handleUnstake = async (pid: number) => {
    if (!wallet.signer || !farmAddress || !unstakeAmount) return;

    setActionLoading(true);
    try {
      const farm = new Contract(farmAddress, LP_FARM_ABI, wallet.signer);
      const amount = parseUnits(unstakeAmount, 18);

      toast.loading('Unstaking LP tokens...', { id: 'unstake' });
      const tx = await farm.withdraw(pid, amount);
      await tx.wait();
      toast.success('Unstaked successfully!', { id: 'unstake' });

      setUnstakeAmount('');
      setSelectedPool(null);
      fetchPools();
    } catch (error: any) {
      console.error('Failed to unstake:', error);
      toast.error(error.reason || 'Failed to unstake', { id: 'unstake' });
    } finally {
      setActionLoading(false);
    }
  };

  const handleClaim = async (pid: number) => {
    if (!wallet.signer || !farmAddress) return;

    setActionLoading(true);
    try {
      const farm = new Contract(farmAddress, LP_FARM_ABI, wallet.signer);

      toast.loading('Claiming rewards...', { id: 'claim' });
      const tx = await farm.claim(pid);
      await tx.wait();
      toast.success('Rewards claimed!', { id: 'claim' });

      fetchPools();
    } catch (error: any) {
      console.error('Failed to claim:', error);
      toast.error(error.reason || 'Failed to claim', { id: 'claim' });
    } finally {
      setActionLoading(false);
    }
  };

  // Check if farm is deployed
  if (!farmAddress) {
    return (
      <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
        <h2 className="text-xl font-bold text-white mb-4">🌾 LP Farming</h2>
        <div className="text-center py-8">
          <p className="text-gray-400 mb-4">Farming system not deployed yet.</p>
          <p className="text-gray-500 text-sm">
            Deploy the LPFarm contract and update config.ts
          </p>
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
        <h2 className="text-xl font-bold text-white mb-4">🌾 LP Farming</h2>
        <div className="flex justify-center py-8">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-500"></div>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* CHORD Balance */}
      {wallet.isConnected && chordTokenAddress && (
        <div className="bg-gradient-to-r from-green-500/20 to-emerald-500/20 rounded-2xl p-6 border border-green-500/30">
          <div className="flex justify-between items-center">
            <div>
              <p className="text-green-400 text-sm mb-1">Your CHORD Balance</p>
              <p className="text-white text-2xl font-bold">
                {parseFloat(chordBalance).toFixed(4)} CHORD
              </p>
            </div>
            <div className="text-4xl">🎵</div>
          </div>
        </div>
      )}

      {/* Farms */}
      <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-xl font-bold text-white">🌾 LP Farming</h2>
          <button
            onClick={fetchPools}
            className="text-gray-400 hover:text-white transition-colors"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
          </button>
        </div>

        {pools.length === 0 ? (
          <p className="text-gray-400 text-center py-8">No farming pools available yet</p>
        ) : (
          <div className="space-y-4">
            {pools.map((pool) => (
              <div key={pool.pid} className="bg-gray-800 rounded-xl p-4">
                {/* Pool Header */}
                <div className="flex justify-between items-center mb-4">
                  <div className="flex items-center gap-3">
                    <div className="flex -space-x-2">
                      <div className="w-8 h-8 rounded-full bg-blue-500 flex items-center justify-center text-white font-bold text-xs border-2 border-gray-800">
                        A
                      </div>
                      <div className="w-8 h-8 rounded-full bg-purple-500 flex items-center justify-center text-white font-bold text-xs border-2 border-gray-800">
                        B
                      </div>
                    </div>
                    <div>
                      <p className="text-white font-semibold">ARCA-ARCB LP</p>
                      <p className="text-gray-400 text-xs">
                        {pool.lpToken.slice(0, 6)}...{pool.lpToken.slice(-4)}
                      </p>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="text-green-400 font-bold text-lg">{pool.apy.toFixed(2)}% APY</p>
                    <p className="text-gray-400 text-xs">
                      {pool.depositFee}% deposit fee
                    </p>
                  </div>
                </div>

                {/* Pool Stats */}
                <div className="grid grid-cols-3 gap-4 mb-4">
                  <div>
                    <p className="text-gray-400 text-xs">Total Staked</p>
                    <p className="text-white font-medium">
                      {parseFloat(pool.totalStaked).toFixed(4)} LP
                    </p>
                  </div>
                  <div>
                    <p className="text-gray-400 text-xs">Your Stake</p>
                    <p className="text-white font-medium">
                      {parseFloat(pool.userStaked).toFixed(4)} LP
                    </p>
                  </div>
                  <div>
                    <p className="text-gray-400 text-xs">Pending Rewards</p>
                    <p className="text-green-400 font-medium">
                      {parseFloat(pool.pendingRewards).toFixed(4)} CHORD
                    </p>
                  </div>
                </div>

                {/* Actions */}
                {wallet.isConnected ? (
                  <>
                    {selectedPool === pool.pid ? (
                      <div className="space-y-3">
                        {/* Stake Input */}
                        <div className="flex gap-2">
                          <input
                            type="number"
                            placeholder={`LP to stake (max: ${parseFloat(pool.lpBalance).toFixed(4)})`}
                            value={stakeAmount}
                            onChange={(e) => setStakeAmount(e.target.value)}
                            className="flex-1 bg-gray-700 text-white px-3 py-2 rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500"
                          />
                          <button
                            onClick={() => setStakeAmount(pool.lpBalance)}
                            className="px-3 py-2 text-green-400 bg-green-400/20 rounded-lg hover:bg-green-400/30"
                          >
                            MAX
                          </button>
                          <button
                            onClick={() => handleStake(pool.pid)}
                            disabled={actionLoading || !stakeAmount}
                            className="px-4 py-2 bg-green-500 text-white rounded-lg hover:bg-green-600 disabled:opacity-50"
                          >
                            Stake
                          </button>
                        </div>

                        {/* Unstake Input */}
                        <div className="flex gap-2">
                          <input
                            type="number"
                            placeholder={`LP to unstake (max: ${parseFloat(pool.userStaked).toFixed(4)})`}
                            value={unstakeAmount}
                            onChange={(e) => setUnstakeAmount(e.target.value)}
                            className="flex-1 bg-gray-700 text-white px-3 py-2 rounded-lg focus:outline-none focus:ring-2 focus:ring-red-500"
                          />
                          <button
                            onClick={() => setUnstakeAmount(pool.userStaked)}
                            className="px-3 py-2 text-red-400 bg-red-400/20 rounded-lg hover:bg-red-400/30"
                          >
                            MAX
                          </button>
                          <button
                            onClick={() => handleUnstake(pool.pid)}
                            disabled={actionLoading || !unstakeAmount}
                            className="px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 disabled:opacity-50"
                          >
                            Unstake
                          </button>
                        </div>

                        <button
                          onClick={() => setSelectedPool(null)}
                          className="w-full text-gray-400 hover:text-white text-sm"
                        >
                          Cancel
                        </button>
                      </div>
                    ) : (
                      <div className="flex gap-2">
                        <button
                          onClick={() => setSelectedPool(pool.pid)}
                          className="flex-1 py-2 bg-gray-700 text-white rounded-lg hover:bg-gray-600 font-medium"
                        >
                          Manage
                        </button>
                        {parseFloat(pool.pendingRewards) > 0 && (
                          <button
                            onClick={() => handleClaim(pool.pid)}
                            disabled={actionLoading}
                            className="px-6 py-2 bg-green-500 text-white rounded-lg hover:bg-green-600 font-medium disabled:opacity-50"
                          >
                            Claim
                          </button>
                        )}
                      </div>
                    )}
                  </>
                ) : (
                  <button
                    onClick={wallet.connect}
                    className="w-full py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 font-medium"
                  >
                    Connect Wallet
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
