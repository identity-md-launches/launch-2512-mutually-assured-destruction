// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Drives MADToken with random transfers, approvals and transferFroms among a fixed set of
///         actors, and with calls that must fail. Keeps a ghost copy of every balance and allowance so
///         the invariants compare the token against an independent model, not against itself.
contract MADHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    MADToken public immutable token;
    address[] internal actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    /// @notice Set when a call that must revert succeeded, or a call that must succeed misbehaved.
    bool public violated;
    string public violation;

    uint256 public calls;
    uint256 public expectedReverts;

    constructor(MADToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            ghostBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _flag(string memory why) internal {
        if (!violated) {
            violated = true;
            violation = why;
        }
    }

    // ------------------------------------------------------------------
    // Calls that must succeed
    // ------------------------------------------------------------------

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        calls++;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        bool ok = token.transfer(to, amount);
        if (!ok) _flag("transfer returned false");

        if (from != to) {
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
        }
        if (token.balanceOf(from) != ghostBalance[from]) _flag("transfer: sender balance wrong");
        if (token.balanceOf(to) != ghostBalance[to]) _flag("transfer: receiver balance wrong");
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        calls++;
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (infinite) amount = type(uint256).max;

        vm.prank(owner);
        bool ok = token.approve(spender, amount);
        if (!ok) _flag("approve returned false");
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        calls++;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = allowed < ghostBalance[from] ? allowed : ghostBalance[from];
        amount = bound(amount, 0, cap);

        vm.prank(spender);
        bool ok = token.transferFrom(from, to, amount);
        if (!ok) _flag("transferFrom returned false");

        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
        if (from != to) {
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
        }
        if (token.allowance(from, spender) != ghostAllowance[from][spender]) _flag("transferFrom: allowance wrong");
    }

    // ------------------------------------------------------------------
    // Calls that must fail, and must change nothing
    // ------------------------------------------------------------------

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        calls++;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = ghostBalance[from];
        excess = bound(excess, 1, type(uint256).max - balance);
        uint256 amount = balance + excess;

        vm.prank(from);
        (bool ok, bytes memory ret) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        _expectRevert(
            ok, ret, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function transferFromAboveAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess)
        external
    {
        calls++;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return; // an infinite allowance has no ceiling to exceed
        excess = bound(excess, 1, type(uint256).max - allowed);
        uint256 amount = allowed + excess;

        vm.prank(spender);
        (bool ok, bytes memory ret) = address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        _expectRevert(
            ok, ret, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        calls++;
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        (bool ok, bytes memory ret) = address(token).call(abi.encodeCall(token.transfer, (address(0), amount)));
        _expectRevert(ok, ret, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        calls++;
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        (bool ok, bytes memory ret) = address(token).call(abi.encodeCall(token.approve, (address(0), amount)));
        _expectRevert(ok, ret, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
    }

    /// @notice Anyone, including the original deployer, tries the usual supply- and holder-control
    ///         selectors. None exists, so every one must revert and leave the supply untouched.
    function tryPrivileged(uint256 callerSeed, uint256 victimSeed, uint256 which, uint256 amount) external {
        calls++;
        address caller = _actor(callerSeed);
        address victim = _actor(victimSeed);
        string[10] memory signatures = [
            "mint(address,uint256)",
            "burn(address,uint256)",
            "burnFrom(address,uint256)",
            "seize(address,uint256)",
            "freeze(address,uint256)",
            "blacklist(address,uint256)",
            "rebase(address,uint256)",
            "pause(address,uint256)",
            "setBalance(address,uint256)",
            "airdrop(address,uint256)"
        ];
        string memory sig = signatures[which % signatures.length];
        vm.prank(caller);
        (bool ok,) = address(token).call(abi.encodeWithSignature(sig, victim, amount));
        expectedReverts++;
        if (ok) _flag(string.concat("privileged call succeeded: ", sig));
    }

    function _expectRevert(bool ok, bytes memory ret, bytes memory expected) internal {
        expectedReverts++;
        if (ok) _flag("a call that must revert succeeded");
        else if (keccak256(ret) != keccak256(expected)) _flag("reverted with an unexpected error");
    }
}

/// @notice Invariants over random call sequences. The token keeps balances, so the fixed supply, the
///         conservation of balances among holders and the allowance accounting must survive any order
///         of calls, including the failing ones.
contract MADTokenInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    MADToken internal token;
    MADHandler internal handler;
    address internal deployer;

    function setUp() public {
        deployer = makeAddr("deployer");
        vm.prank(deployer);
        token = new MADToken();

        address[] memory actors = new address[](6);
        actors[0] = deployer;
        actors[1] = makeAddr("alice");
        actors[2] = makeAddr("bob");
        actors[3] = makeAddr("carol");
        actors[4] = makeAddr("distributor");
        actors[5] = makeAddr("poolManager");

        handler = new MADHandler(token, actors);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.actorAt(i));
        }
        // Every transfer stays among the actors, so they hold the whole supply between them.
        assertEq(sum, SUPPLY);
        assertEq(sum, token.totalSupply());
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesMatchModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address a = handler.actorAt(i);
            assertEq(token.balanceOf(a), handler.ghostBalance(a));
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_allowancesMatchModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            for (uint256 j; j < n; ++j) {
                address o = handler.actorAt(i);
                address s = handler.actorAt(j);
                assertEq(token.allowance(o, s), handler.ghostAllowance(o, s));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_noCallMisbehaved() public view {
        assertFalse(handler.violated(), handler.violation());
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_zeroAddressAndTokenHoldNothing() public view {
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_metadataIsFixed() public view {
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
    }
}
