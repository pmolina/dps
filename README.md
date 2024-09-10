# Decentralized Pension System (DPS)

## Overview

The Decentralized Pension System (DPS) is a proof-of-concept smart contract implementation that allows users to create and manage their own pension funds using any ERC20 token. This system leverages blockchain technology to provide a transparent, secure, and self-managed pension solution.

## Features

- **ERC20 Token Support**: The contract can be deployed for any ERC20 token, allowing for multiple markets.
- **Flexible Withdrawals**: Funds can be withdrawn at any time by the account holder.
- **Proof of Life**: Regular interactions with the contract serve as proof of life, ensuring the account holder's continued access.
- **Customizable Fallback Wallet**: Users can set and update a fallback wallet to receive funds in case of prolonged inactivity. If not set, the user's own address is used as the fallback.
- **Customizable Fallback Period**: Users can set their own fallback period (between 90 days and 3 years).
- **Open Fallback Withdrawal Initiation**: After the fallback period elapses without activity, any wallet can initiate a withdrawal, but funds are sent only to the designated fallback wallet or the user's address if no fallback is set.
- **Pausable**: The contract can be paused by the owner in case of emergencies.

## Smart Contract

The core of the DPS is the `StablecoinVault` smart contract. Key components include:

- Deposit and withdrawal functions for the specified ERC20 token
- Proof of life mechanism, automatically updating on interactions
- Fallback wallet system with customizable periods
- Balance tracking for each user
- Utilizes OpenZeppelin contracts for enhanced security (ReentrancyGuard, Ownable, Pausable)

## Multiple Markets

To support multiple ERC20 tokens, the contract should be deployed separately for each token. This allows for independent markets for different tokens, each with its own set of users, balances, and configurations.

## Testing

A comprehensive test suite is implemented in `test/StablecoinVault.test.js`, covering all major functionalities:

- Deployment
- Deposits and withdrawals
- Proof of life updates
- Fallback wallet operations
- Owner functions (pause/unpause)
- Uses MockERC20 tokens to simulate ERC20 token interactions

## Usage

1. Deploy the StablecoinVault contract with the address of the desired ERC20 token.
2. Users set their fallback wallet using the `setFallbackWallet` function.
3. Users set their fallback period using the `setUserFallbackPeriod` function.
4. Users can deposit tokens using the `deposit` function.
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
