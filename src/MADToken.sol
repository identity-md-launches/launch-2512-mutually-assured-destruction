// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mutually Assured Destruction (MAD)
/// @notice A fixed-supply ERC-20. The whole supply is minted once, to the deployer, in the
///         constructor. There is no owner, no minter, no pause, no blocklist, no fee on transfer
///         and no upgrade path: after deployment nobody, including the deployer, holds any power
///         over the token that an ordinary holder does not.
/// @dev The deployer is `msg.sender` of the constructor. On an IdentityMD launch that is the
///      ProjectFactory, which distributes the supply (swarm share, pool seed, remainder) itself.
///      The constructor calls no other contract, so it deploys on an empty chain.
contract MADToken is ERC20 {
    /// @notice Token name returned by `name()`.
    string public constant TOKEN_NAME = "Mutually Assured Destruction";

    /// @notice Token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "MAD";

    /// @notice Number of decimals. Same as the ERC20 default; restated so the value is explicit.
    uint8 public constant DECIMALS = 18;

    /// @notice The entire supply: 1,000,000,000 MAD in minor units (18 decimals).
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice Emitted once, when the supply is minted to the deployer.
    /// @param deployer The address that received the whole supply.
    /// @param amount The amount minted, equal to `TOTAL_SUPPLY`.
    event SupplyMinted(address indexed deployer, uint256 amount);

    /// @notice Mints `TOTAL_SUPPLY` to `msg.sender`. Nothing can mint afterwards.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
