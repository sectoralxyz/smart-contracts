<p align="center">
  <img src="https://sectoral.xyz/images/logo-bg.png" alt="Sectoral" width="88" height="88">
</p>

<h1 align="center">Sectoral Contracts</h1>

<p align="center">
  <a href="https://sectoral.xyz">sectoral.xyz</a> &nbsp;·&nbsp;
  <a href="https://docs.sectoral.xyz">Docs</a> &nbsp;·&nbsp;
  <a href="https://x.com/sectoralxyz">@sectoralxyz</a>
</p>

This is the on-chain half of Sectoral, a private neobank built for humans and for the AI agents that act for them. Every contract here is written for Robinhood Chain (an Arbitrum Nitro rollup) and deploys to chain ID 4663.

There are two layers. At the bottom sits `ConfidentialToken`, a USDG wrapper that stores balances and transfer amounts as ElGamal ciphertexts on the alt_bn128 curve; an on-chain verifier checks that each transfer is valid while learning none of the numbers involved. Everything else is the scaffolding that makes an encrypted balance behave like a bank account: persistent `.sectoral` names, agents held to limits the chain enforces, a queue for payments a human should review first, request-to-pay links, and receipts that prove a disclosure took place.

Sender and recipient addresses are visible the whole way through. Only the amount moving between them is hidden.

## Why the token alone is not enough

Encrypting a balance gives you privacy and that is all it gives you. It has no way to show that `gwen.sectoral` owns a given wallet, that an agent has used up its allowance for the day, that a payment request expired without being paid, or that the owner responded to an auditor last March. Putting any of that inside the token would mean more circuits to prove and more ways to fail. Instead it lives next to the token as plain contract state, and the client combines both at settlement time.

## Contents

| Contract | Responsibility |
|---|---|
| `ProtocolAuthority` | Holds the admin and compliance roles, the pause switch and fee routing. Never holds funds. |
| `AccountRegistry` | A single record for each wallet, unique `.sectoral` handles, and KYC tiers set by the compliance role. |
| `AgentController` | Agent records, on-chain spend policies, agent vaults, the approval queue, signer rotation and revocation. |
| `RequestLedger` | Payment requests, including confidential ones where a commitment takes the place of the amount. |
| `DisclosureLog` | A timestamped record that a disclosure occurred, with neither the counterparty named nor the proof published. |
| `confidential/ConfidentialToken` | The USDG wrapper with encrypted balances: register, deposit, transfer and withdraw. |
| `confidential/AltBn128` | BN254 group math on top of the `0x06` and `0x07` precompiles, used to manipulate ciphertexts. |
| `confidential/IConfidentialTransferVerifier` | The interface a deployed Groth16 verifier has to satisfy. `StubTransferVerifier` is a bring-up stand-in that verifies nothing. |
| `fees/FeeSchedule` | The single source of pricing. Every value-moving call looks up its fee here. |

## How an agent pays

Agents sign with `agentSigner`, a key kept by whichever system runs the agent. That key is intentionally limited. It can touch only money already deposited in a vault the contract controls, only in the agent's one settlement token, and only inside the policy its owner set. No funds are ever held under the agent's own key, so if the key leaks the response is to pause or revoke the agent, not to race an attacker for the balance.

Each vault is an internal balance kept by `AgentController`. `fundAgent` credits it with the amount that actually arrived, which means a fee-on-transfer token cannot overstate what is there. Agents have no access to each other's balances.

The `hitlThreshold` setting chooses between two paths for a payment:

- `payInvoice` settles immediately. It checks the per-transaction cap, the rolling 24-hour window, the recipient allowlist, and that the amount falls within the threshold. The window resets itself the first time a payment arrives more than a day after the window began, so no one ever needs to trigger a reset.
- `queueInvoice` holds anything over the threshold without moving funds. The allowlist and per-transaction cap are enforced right away, which keeps the queue free of payments that could never succeed. The daily cap is intentionally checked only at approval, since a payment that fit when it was queued may not fit by the time a person reviews it.

From there the owner calls either `approvePending`, which checks the policy again against current state before releasing funds, or `rejectPending`, which deletes the entry. No transfer happened in the first place, so rejecting leaves nothing to reverse.

On both paths the x402 `invoiceId` is passed through to `AgentPaymentExecuted`, giving an operator's webhook something to reconcile against.

Ahead of either call, an agent or a front end can ask `routeFor(agentId, recipient, amount)`. It performs the same checks as a view and returns `Settles`, `Queues` or `Refused`. To list the agents a wallet owns, use `agentIdsOf`, which follows the same pattern the request ledger and disclosure log use for their records.

Three owner controls sit above all of this. `setAgentStatus` pauses and resumes an agent and leaves its vault and policy alone. `rotateAgentSigner` swaps in a new key and keeps the vault, policy and history intact, giving a leaked key a recovery route short of tearing the agent down. `revokeAgent` cannot be undone and sends any remaining balance back to the owner in the same transaction.

## How a confidential transfer works

Each account registers an ElGamal public key and holds a single ciphertext balance. After that:

- `deposit` wraps the underlying asset by adding `amount * G` to the message component with zero randomness. This is the usual Zether funding step, and it means the depositor can still read the running balance with their own view key.
- `confidentialTransfer` accepts two ElGamal deltas, one encrypting `-amount` for the sender and one encrypting `+amount` for the recipient, along with a proof. The verifier requires that both encode the same non-negative amount and that the sender remains solvent. The contract then adds each delta to the matching balance by point addition, and that is why no amount ever shows up in calldata or storage.
- `withdraw` unwraps, backed by a proof that the encrypted balance is large enough. The amount is public at this step, since the ERC-20 transfer that follows would reveal it regardless.

The verifier is a separate contract set through `setVerifier`, so circuits can be upgraded without moving any balances. This layer also has a freeze of its own, separate from the protocol-wide pause. It halts value movement but keeps registration and verifier rotation working, so a verifier under suspicion can be replaced without locking anyone out.

## Fees

A single contract handles all pricing. `FeeSchedule.quoteFee(payer, amount)` returns both the fee and the rate behind it, and the app and SDK call that same view to show users their current rate before they commit.

```
grossFee  = amount * baseFeeBps / 10_000
feeAmount = min(grossFee, feeCap)
```

There is one rate for every account. By default it is a flat 0.10%, with a cap of 5 USDG.

Fees are off at deployment. Nothing is charged until `ProtocolAuthority.setFeeConfig(treasury, feeSchedule)` sets both values, and unsetting either one turns fees off everywhere again. `AgentController` pays the fee out of the agent's vault and deliberately leaves it out of the policy calculation, because those limits cover what the agent spends and not what the protocol charges for carrying the payment. `RequestLedger` adds the fee to what the payer owes, so the recipient receives the full amount.

## Trust assumptions

The protocol takes custody of no user funds. Account assets remain in the account holder's own wallet. Agent vaults are the only pooled balances, and they exist only so that a spend policy is enforced by code instead of promised by a server.

The admin role can reassign the other roles, operate the pause and set up fee routing. It has no power to move user funds, mint anything or decrypt a balance. Transferring the admin role is a two-step process (the current admin nominates and the nominee accepts), so a typo in an address cannot leave the protocol with no admin.

Pausing halts value movement but intentionally keeps identity and agent settings editable. During an incident a user must still be able to pause or revoke an agent, and a freeze that blocked that would fail exactly when it matters most.

The compliance role sets KYC tiers and nothing more. It cannot move funds, stop a transfer or view an amount. The admin can replace it directly with `setComplianceAuthority`, with no need to restate the admin address.

## Directory structure

```
contracts/
  src/
    ProtocolAuthority.sol        roles, pause, fee routing
    AccountRegistry.sol          records, handles, KYC tiers
    AgentController.sol          agents, policy, approval queue, x402
    RequestLedger.sol            request-to-pay, confidential commitments
    DisclosureLog.sol            disclosure receipts
    confidential/                ConfidentialToken, AltBn128, verifier interface
    fees/                        FeeSchedule
    interfaces/                  IERC20, IProtocolAuthority, IAccountRegistry
    libraries/                   SafeTransferLib, ReentrancyGuard, shared errors
  script/
    Deploy.s.sol                 production deployment, driven by .env
    DeployTestnet.s.sol          testnet bring-up against a mock USDG
  test/                          Foundry suite
```

## Build and test

[Foundry](https://book.getfoundry.sh/) is required.

```bash
forge install foundry-rs/forge-std --no-git
forge build
forge test
```

The compiler is fixed at solc 0.8.24 with the Paris EVM target, so the output never relies on an opcode the rollup has not enabled. `via_ir` is turned on because `createAgent` receives a large policy as individual arguments, which exceeds the normal stack depth.

## Deployment

Make a copy of `.env.example` named `.env`, then fill in the deployer key, the compliance authority, the USDG address and, when one is available, the production verifier. If `TRANSFER_VERIFIER_ADDRESS` is left blank, the script deploys `StubTransferVerifier` so the token can be tested during bring-up. The stub verifies nothing and has to be swapped out with `ConfidentialToken.setVerifier` before any real value is involved.

```bash
# Testnet first, chain ID 46630
forge script script/Deploy.s.sol:Deploy \
  --rpc-url robinhood_testnet --broadcast

# Mainnet, chain ID 4663
forge script script/Deploy.s.sol:Deploy \
  --rpc-url robinhood --broadcast --verify --verifier blockscout
```

Setting `TREASURY` also deploys the fee schedule and connects fee routing. Without it the protocol launches with fees disabled, which is the suggested first step.

Contract verification is done through Blockscout:

```bash
forge verify-contract <address> src/AgentController.sol:AgentController \
  --chain-id 4663 --verifier blockscout \
  --verifier-url https://robinhoodchain.blockscout.com/api/
```

`DeployTestnet.s.sol` is there because testnet has no official USDG. It mints a six-decimal substitute, makes the deployer the compliance authority and deploys the bring-up verifier. None of those steps should ever reach mainnet.

## Network details

| | Mainnet | Testnet |
|---|---|---|
| Chain ID | 4663 | 46630 |
| RPC | `https://rpc.mainnet.chain.robinhood.com` | `https://rpc.testnet.chain.robinhood.com` |
| Explorer | robinhoodchain.blockscout.com | explorer.testnet.chain.robinhood.com |
| Gas token | ETH | ETH |

## Testnet deployment

The protocol is live on Robinhood Chain testnet (chain ID 46630), deployed with `DeployTestnet.s.sol` on 2026-10-04. The settlement asset is the testnet USDG stand-in and the verifier is the bring-up stub, so no amount here carries real value. Every contract below is source-verified on the testnet explorer.

| Contract | Address |
|---|---|
| `ProtocolAuthority` | [`0xde0cc85F9F168576eC429D8E023871c623580F96`](https://explorer.testnet.chain.robinhood.com/address/0xde0cc85F9F168576eC429D8E023871c623580F96) |
| `AccountRegistry` | [`0x7d14b198B7D4Cf50287209d102cCE39388A861b0`](https://explorer.testnet.chain.robinhood.com/address/0x7d14b198B7D4Cf50287209d102cCE39388A861b0) |
| `AgentController` | [`0x1458062e466128791044bE256eD7A866f3825Af7`](https://explorer.testnet.chain.robinhood.com/address/0x1458062e466128791044bE256eD7A866f3825Af7) |
| `RequestLedger` | [`0xa365489ee4aAdA03BF4135c342e61cc8399ef004`](https://explorer.testnet.chain.robinhood.com/address/0xa365489ee4aAdA03BF4135c342e61cc8399ef004) |
| `DisclosureLog` | [`0xf397327d4FD2Ff1B527be56D682Ba4E2b95B88A2`](https://explorer.testnet.chain.robinhood.com/address/0xf397327d4FD2Ff1B527be56D682Ba4E2b95B88A2) |
| `ConfidentialToken` | [`0x75C62a67f543045D3A6C1229628Af5fAf0097633`](https://explorer.testnet.chain.robinhood.com/address/0x75C62a67f543045D3A6C1229628Af5fAf0097633) |
| `StubTransferVerifier` | [`0xd641b9D71ABBbA5D51c0a4dF7167f77a8Dc3E95C`](https://explorer.testnet.chain.robinhood.com/address/0xd641b9D71ABBbA5D51c0a4dF7167f77a8Dc3E95C) |
| USDG (testnet stand-in) | [`0xCDF02eC32cd2A6ad7610A2e6a8fd95A9DeC98d16`](https://explorer.testnet.chain.robinhood.com/address/0xCDF02eC32cd2A6ad7610A2e6a8fd95A9DeC98d16) |
| Deployer, admin and compliance authority | [`0x6bE6CD2eDc4E903fD5c869A3e8b766A58546D9f4`](https://explorer.testnet.chain.robinhood.com/address/0x6bE6CD2eDc4E903fD5c869A3e8b766A58546D9f4) |

Fees are off on this deployment: `setFeeConfig` has not been called, so no `FeeSchedule` is wired in.
