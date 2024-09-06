# Decentralized Pension System (DPS)

## Overview

The Decentralized Pension System (DPS) is a proof-of-concept smart contract implementation that allows users to create and manage their own pension funds using stablecoins. This system leverages blockchain technology to provide a transparent, secure, and self-managed pension solution.

## Features

- **Stablecoin Deposits**: Users can deposit USDC and USDT into their personal pension vault.
- **Flexible Withdrawals**: Funds can be withdrawn at any time by the account holder.
- **Proof of Life**: Regular interactions with the contract serve as proof of life, ensuring the account holder's continued access.
- **Fallback Wallet**: Users can designate a fallback wallet to access funds in case of prolonged inactivity.
- **Customizable Fallback Period**: The contract owner can set a fallback period between 90 days and 3 years.
- **Pausable**: The contract can be paused in case of emergencies.

## Smart Contract

The core of the DPS is the `StablecoinVault` smart contract. Key components include:

- Deposit and withdrawal functions
- Proof of life mechanism
- Fallback wallet system
- Balance tracking for each user and token

## Getting Started

1. Clone the repository
2. Install dependencies: `npm install`
3. Compile the contract: `npx hardhat compile`
4. Run tests: `npx hardhat test`
5. Deploy to a testnet or local network: `npx hardhat run scripts/deploy.js --network <your-network>`

## Usage

- Users deposit stablecoins into their vault
- Regular interactions (deposits, withdrawals, or explicit updates) serve as proof of life
- Set a fallback wallet for emergency access
- Withdraw funds as needed for pension payments

## Security

The contract includes several security measures:

- ReentrancyGuard to prevent reentrancy attacks
- Ownable for access control
- Pausable for emergency stops

## Disclaimer

This is a proof of concept and not intended for production use without further development, auditing, and legal compliance checks.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request with your improvements.
