# Decentralized Pension System (DPS)

## Overview

The Decentralized Pension System (DPS) is a proof-of-concept smart contract implementation that allows users to create and manage their own pension funds using stablecoins. This system leverages blockchain technology to provide a transparent, secure, and self-managed pension solution.

## Features

- **Multi-Stablecoin Support**: Users can deposit USDC, USDT, and DAI into their personal pension vault.
- **Flexible Withdrawals**: Funds can be withdrawn at any time by the account holder.
- **Proof of Life**: Regular interactions with the contract serve as proof of life, ensuring the account holder's continued access.
- **Customizable Fallback Wallet**: Users can set and update a fallback wallet to receive funds in case of prolonged inactivity. If not set, the user's own address is used as the fallback.
- **Customizable Fallback Period**: Users can set their own fallback period (between 90 days and 3 years).
- **Open Fallback Withdrawal Initiation**: After the fallback period elapses without activity, any wallet can initiate a withdrawal, but funds are sent only to the designated fallback wallet or the user's address if no fallback is set.
- **Pausable**: The contract can be paused by the owner in case of emergencies.

## Smart Contract

The core of the DPS is the `StablecoinVault` smart contract. Key components include:

- Deposit and withdrawal functions for USDC, USDT, and DAI
- Proof of life mechanism, automatically updating on interactions
- Fallback wallet system with customizable periods
- Balance tracking for each user and token
- Utilizes OpenZeppelin contracts for enhanced security (ReentrancyGuard, Ownable, Pausable)

## Testing

A comprehensive test suite is implemented in `test/StablecoinVault.test.js`, covering all major functionalities:

- Deployment
- Deposits and withdrawals
- Proof of life updates
- Fallback wallet operations
- Owner functions (pause/unpause)
- Uses MockERC20 tokens to simulate stablecoin interactions

## Usage

1. Deploy the StablecoinVault contract with addresses for USDC, USDT, and DAI.
2. Users set their fallback wallet using the `setFallbackWallet` function.
3. Users set their fallback period using the `setUserFallbackPeriod` function.
4. Users can deposit stablecoins using the `deposit` function.
5. Users can withdraw funds at any time when the contract is not paused.
6. Regular interactions (deposits, withdrawals) automatically update the proof of life.
7. Users can manually update their proof of life by calling the `updateProofOfLife` function.
8. If a user is inactive beyond their fallback period, any wallet can initiate a withdrawal to the designated fallback wallet or the user's address if no fallback is set.

## Development

This project uses Hardhat for development and testing. To set up the development environment:

1. Install dependencies: `npm install`
2. Compile contracts: `npx hardhat compile`
3. Run tests: `npx hardhat test`
4. Deploy (local network): `npx hardhat run scripts/deploy.js`

## Security

The contract incorporates several security measures:

- ReentrancyGuard to prevent reentrancy attacks
- Ownable for access control of critical functions
- Pausable for emergency stops
- Utilizes OpenZeppelin's secure, audited contract implementations

## Disclaimer

This is a proof of concept and not intended for production use without further development, auditing, and legal compliance checks.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request with your improvements.

## License

The license for this project is currently undefined and under consideration. Please check back later for updates on the licensing terms.
