# Mutually Assured Destruction (MAD)

A fixed-supply ERC-20 token built with Foundry and OpenZeppelin Contracts v5.1.0.

| Parameter        | Value                                             |
| ---------------- | ------------------------------------------------- |
| Solidity name    | `MADToken` (`src/MADToken.sol`)                   |
| `name()`         | `Mutually Assured Destruction`                    |
| `symbol()`       | `MAD`                                             |
| `decimals()`     | `18`                                              |
| `totalSupply()`  | `1000000000000000000000000000` (1,000,000,000 MAD) |
| Constructor args | none                                              |
| Owner / admin    | none                                              |

## Behaviour

- The constructor mints the whole supply once, to `msg.sender`, and emits `Transfer(0, deployer, supply)`
  and `SupplyMinted(deployer, supply)`.
- The token is a plain OpenZeppelin `ERC20`. Transfers, `approve`, `transferFrom` and allowances behave
  exactly as the standard describes: no fee, no burn on transfer, no reflections, no blocklist, no pause.
- There is no `mint`, `burn`, `burnFrom`, owner, minter role, pause, blocklist, freeze, upgrade path or
  `selfdestruct`. The supply can never change after deployment, in either direction.
- The constructor calls no other contract, so the token deploys on an empty chain.

## Assumptions

- The deployer is whoever runs the constructor. On an IdentityMD launch that is the ProjectFactory,
  which receives the whole supply and distributes it itself (swarm share to the MerkleDistributor, pool
  seed through the Uniswap v4 PoolManager, remainder to the requester). Because transfers are untaxed,
  every launch flow arrives whole and no address needs to be exempted, so the constructor takes no
  factory, pool manager or launch-number argument.
- The brief asks only for name, symbol and supply. No transfer rules, taxes, burns or governance were
  requested, so none were added. A fixed supply also means no owner is needed, and none exists.
- `decimals()` is 18, the ERC-20 default, restated as the `DECIMALS` constant so it is explicit.

## Deployment parameters

The token has no constructor arguments and no post-deployment configuration.

Launch values decided by IdentityMD (recorded in the manifest step, not here):

- Chain: Ethereum mainnet (chain id 1).
- Paired currency: FWA, `0xa0df17b5ac76ababa36e1450e2cbcd18a620c845`.
- Pool fee 12500 (1.25%), tick spacing 60, initial price `79228162514264337593543950336` (provenance only;
  the deployer derives the real opening price from the market cap and supply).
- Economics: 80% of supply seeds the pool at a 2,000,000 FWA market cap; 10% to the swarm; 10% to
  `0x1ee3ffadfe138415a2ddaedeebe5f46616fa413d`.

`script/DeployMADToken.s.sol` is a reviewable reference deployment for local or manual use. It reads no
environment variables; `deploy()` is called directly by the tests and `run()` wraps it in a broadcast
using whatever sender forge is given. It is not used by the IdentityMD launch, which deploys the
creation code through the factory.

## After launch

Nothing to configure. The token has no owner-settable values.

## Operational responsibilities

- **Holders** are solely responsible for their balances. No party can move, freeze or seize a holder's
  tokens; a lost key is an unrecoverable loss of those tokens.
- **The deployer / factory** holds the whole supply immediately after the constructor runs and is
  responsible for distributing it. The token itself enforces nothing about that distribution.
- **Nobody** has an ongoing operational role: there is no owner to rotate, no parameter to tune, no
  pause to lift and no upgrade to apply. The contract is final at deployment.
- **Allowances** follow the standard: approving `type(uint256).max` grants a spender indefinite access
  until revoked. Users should approve only what they intend to spend.
- **Verification** of the source on a block explorer after deployment belongs to the launch's deployer.

## Security notes

- Checked against the pinned eth-security checklist: no reentrancy surface (no external calls), no
  arithmetic beyond the audited OpenZeppelin ERC20, no access control because there is nothing to
  control, no proxies, no delegatecall, no `selfdestruct`, no `abi.encodePacked` of dynamic values.
- Tests assert the runtime bytecode contains no reachable `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`
  and fits the EIP-170 size limit.
- Tools run locally: `forge build`, `forge test` (with the verifier's fuzz seed), `forge fmt --check`.
  Slither was not available on this machine.
- Passing tests are not an audit. The contract is a thin wrapper over OpenZeppelin ERC20 v5.1.0 with no
  custom logic beyond the constructor mint.

## Repository layout

```
foundry.toml                 solc 0.8.26, optimizer on, bytecode_hash = "none", no ffi / fs access
remappings.txt               forge-std and @openzeppelin/contracts remappings
src/MADToken.sol             the token
script/DeployMADToken.s.sol  reference deploy script
test/MADToken.t.sol          unit and fuzz tests (success and failure paths)
test/DeployMADToken.t.sol    tests the deploy function directly
lib/forge-std                forge-std v1.9.7 (vendored, src only)
lib/openzeppelin-contracts   OpenZeppelin Contracts v5.1.0 (vendored, contracts only)
```

## Building and testing

```
forge build
forge test
forge fmt --check
```

Tests read no environment variables and pass in any order and in parallel.
