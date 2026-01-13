import { ARC_TESTNET } from '../config';

interface HeaderProps {
  wallet: {
    isConnected: boolean;
    address: string | null;
    isConnecting: boolean;
    connect: () => void;
    disconnect: () => void;
  };
}

export default function Header({ wallet }: HeaderProps) {
  const formatAddress = (address: string) => {
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  };

  return (
    <header className="border-b border-white/10 bg-arc-dark/50 backdrop-blur-xl">
      <div className="container mx-auto px-4 py-4 flex items-center justify-between">
        {/* Logo */}
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-arc-primary to-arc-secondary flex items-center justify-center">
            <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
            </svg>
          </div>
          <div>
            <h1 className="text-xl font-bold text-white">CredArc</h1>
            <p className="text-xs text-gray-500">Testnet</p>
          </div>
        </div>

        {/* Navigation */}
        <nav className="hidden md:flex items-center gap-6">
          <a
            href={ARC_TESTNET.explorer}
            target="_blank"
            rel="noopener noreferrer"
            className="text-gray-400 hover:text-white transition-colors"
          >
            Explorer
          </a>
          <a
            href="https://faucet.circle.com"
            target="_blank"
            rel="noopener noreferrer"
            className="text-gray-400 hover:text-white transition-colors"
          >
            Faucet
          </a>
          <a
            href="https://docs.arc.network"
            target="_blank"
            rel="noopener noreferrer"
            className="text-gray-400 hover:text-white transition-colors"
          >
            Docs
          </a>
        </nav>

        {/* Wallet */}
        <div className="flex items-center gap-3">
          {wallet.isConnected ? (
            <div className="flex items-center gap-3">
              <div className="hidden sm:flex items-center gap-2 px-3 py-1.5 bg-arc-dark rounded-lg">
                <div className="w-2 h-2 rounded-full bg-green-400" />
                <span className="text-sm text-gray-400">Arc Testnet</span>
              </div>
              <button
                onClick={wallet.disconnect}
                className="btn-connect flex items-center gap-2"
              >
                <span>{formatAddress(wallet.address!)}</span>
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                </svg>
              </button>
            </div>
          ) : (
            <button
              onClick={wallet.connect}
              disabled={wallet.isConnecting}
              className="btn-connect"
            >
              {wallet.isConnecting ? 'Connecting...' : 'Connect Wallet'}
            </button>
          )}
        </div>
      </div>
    </header>
  );
}
