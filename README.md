# FreelanceChain

A decentralized platform for freelance work built on the Stacks blockchain, leveraging Clarity smart contracts for secure escrow, reputation systems, and dispute resolution.

## Overview

FreelanceChain connects clients and freelancers in a trustless environment, using blockchain technology to ensure fairness, transparency, and security in freelance engagements. The platform features:

- **Escrow-based payments**: Funds are locked in smart contracts and released upon milestone completion
- **Decentralized reputation system**: Both clients and freelancers build on-chain reputation scores
- **Dispute resolution**: Community-governed arbitration process for resolving conflicts
- **Role-based access control**: Clear permissions and security model
- **DAO-based governance**: Community participation in platform decisions

## Prerequisites

- Clarinet v1.0.0 or higher
- Stacks blockchain node (optional for local testing)
- NodeJS v16+ (for UI development)

## Installation & Setup

1. Clone the repository
```bash
git clone https://github.com/yourusername/freelance-chain.git
cd freelance-chain
```

2. Install Clarinet (if not already installed)
```bash
curl -sS -o- https://raw.githubusercontent.com/hirosystems/clarinet/main/install.sh | bash
```

3. Initialize the project
```bash
clarinet integrate
```

## Testing

Run tests using Clarinet:

```bash
clarinet check
```

This will execute all tests in the `tests/` directory, verifying the contract functionality.

## Contract Structure

### Core Modules

- **access-control.clar**: Role-based permissions system
- **freelance-registry.clar**: Job registration and metadata
- **proposal-manager.clar**: Proposal submission and acceptance
- **escrow-vault.clar**: Secure fund management and milestone-based payments
- **reputation-score.clar**: On-chain reputation tracking
- **dispute-resolution.clar**: Dispute handling and arbitration
- **arbitrator-dao.clar**: Decentralized arbitration governance
- **token-utils.clar**: Token operations and safety utilities

## Usage Examples

### Posting a Job

```clarity
(contract-call? .freelance-registry create-job
  "Web Application Development"
  "Build a React frontend for our DeFi platform"
  u5000000000 ;; 5000 STX
  u1209600    ;; 2 weeks deadline
  "development"
  (list "react" "web3" "stacks")
  none
  u80)
```

### Submitting a Proposal

```clarity
(contract-call? .proposal-manager create-proposal
  u1  ;; job-id
  u4500000000  ;; 4500 STX bid
  u1036800     ;; 12 days delivery
  "I can build this with my expertise in React and Stacks blockchain integration")
```

### Creating Escrow with Milestones

```clarity
(contract-call? .escrow-vault create-escrow
  u1  ;; job-id
  u4500000000  ;; total amount
  (list
    { amount: u1500000000, description: "Frontend wireframes", released: false }
    { amount: u1500000000, description: "Working prototype", released: false }
    { amount: u1500000000, description: "Final delivery", released: false }
  )
  .freelance-registry
  .token-utils)
```

### Rating a Freelancer

```clarity
(contract-call? .reputation-score rate-user
  'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG  ;; freelancer address
  u1  ;; job-id
  u5  ;; 5-star rating
  "Excellent work, delivered on time and with great quality"
  .freelance-registry)
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.