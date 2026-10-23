// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Stands in for the launch factory: deploys the token with CREATE2 and splits the supply in the
///         same call, the way `launchCustom` does in one transaction.
contract FactoryProbe {
    function launch(bytes32 salt, address distributor, address poolManager, address requester, uint256 poolBps)
        external
        returns (MADToken token, uint256 swarm, uint256 pool, uint256 remainder)
    {
        token = new MADToken{salt: salt}();
        uint256 supply = token.totalSupply();
        require(token.balanceOf(address(this)) == supply, "factory does not hold the supply");
        swarm = supply * 1_000 / 10_000;
        pool = supply * poolBps / 10_000;
        remainder = supply - swarm - pool;
        require(token.transfer(distributor, swarm), "swarm transfer");
        require(token.transfer(poolManager, pool), "pool transfer");
        require(token.transfer(requester, remainder), "remainder transfer");
    }
}

contract MADTokenLaunchTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    FactoryProbe internal factory;
    address internal distributor = makeAddr("distributor");
    address internal poolManager = makeAddr("poolManager");
    address internal requester = makeAddr("requester");

    function setUp() public {
        factory = new FactoryProbe();
    }

    function test_launchSplitsArriveWhole() public {
        (MADToken token, uint256 swarm, uint256 pool, uint256 remainder) =
            factory.launch(bytes32(uint256(1)), distributor, poolManager, requester, 8_000);
        assertEq(swarm, 100_000_000 ether);
        assertEq(pool, 800_000_000 ether);
        assertEq(remainder, 100_000_000 ether);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.balanceOf(requester), remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_create2AddressIsPredictable() public {
        bytes32 salt = bytes32(uint256(42));
        address predicted = vm.computeCreate2Address(salt, keccak256(type(MADToken).creationCode), address(factory));
        (MADToken token,,,) = factory.launch(salt, distributor, poolManager, requester, 8_000);
        assertEq(address(token), predicted);
    }

    function test_sameSaltCannotDeployTwice() public {
        bytes32 salt = bytes32(uint256(7));
        factory.launch(salt, distributor, poolManager, requester, 8_000);
        vm.expectRevert();
        factory.launch(salt, distributor, poolManager, requester, 8_000);
    }

    /// @notice Claims out of the distributor are untaxed: the last claimant gets its share whole and the
    ///         distributor ends empty.
    function testFuzz_distributorClaimsDrainExactly(uint256 claimants, uint256 seed) public {
        claimants = bound(claimants, 1, 50);
        (MADToken token, uint256 swarm,,) = factory.launch(bytes32(seed), distributor, poolManager, requester, 8_000);
        uint256 share = swarm / claimants;
        uint256 paid;
        for (uint256 i; i < claimants; ++i) {
            address claimant = address(uint160(0x1000 + i));
            uint256 amount = i == claimants - 1 ? swarm - paid : share;
            vm.prank(distributor);
            assertTrue(token.transfer(claimant, amount));
            assertEq(token.balanceOf(claimant), amount);
            paid += amount;
        }
        assertEq(paid, swarm);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @notice A pool manager can pay out whatever it holds and pull exactly what it is approved for.
    function testFuzz_poolSettlementIsExact(uint256 buy, uint256 sell) public {
        (MADToken token,, uint256 pool,) = factory.launch(bytes32(0), distributor, poolManager, requester, 8_000);
        address trader = makeAddr("trader");
        buy = bound(buy, 1, pool);
        vm.prank(poolManager);
        assertTrue(token.transfer(trader, buy));
        assertEq(token.balanceOf(trader), buy);

        sell = bound(sell, 1, buy);
        vm.prank(trader);
        token.approve(poolManager, sell);
        vm.prank(poolManager);
        assertTrue(token.transferFrom(trader, poolManager, sell));
        assertEq(token.balanceOf(trader), buy - sell);
        assertEq(token.balanceOf(poolManager), pool - buy + sell);
        assertEq(token.allowance(trader, poolManager), 0);
    }

    function test_factoryCannotPullFromHoldersAfterLaunch() public {
        (MADToken token,,,) = factory.launch(bytes32(0), distributor, poolManager, requester, 8_000);
        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        token.transferFrom(requester, address(factory), 1);
    }
}

/// @notice Boundary inputs the main suite does not pin.
contract MADTokenEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    MADToken internal token;
    address internal holder;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        holder = makeAddr("holder");
        vm.prank(holder);
        token = new MADToken();
    }

    function test_transferWholeSupply() public {
        vm.prank(holder);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
    }

    function test_transferOneWei() public {
        vm.prank(holder);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
    }

    function test_transferMaxUintReverts() public {
        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_transferOneWeiAboveSupplyReverts() public {
        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
    }

    function test_transferToTokenContractIsAnOrdinaryTransfer() public {
        // No special handling: the tokens are stuck there, but nothing is burned or reflected.
        vm.prank(holder);
        assertTrue(token.transfer(address(token), 1 ether));
        assertEq(token.balanceOf(address(token)), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerNeedsAllowanceForOwnTransferFrom() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        token.transferFrom(holder, alice, 1);
    }

    function test_transferFromZeroAmountNeedsNoAllowance() public {
        vm.prank(bob);
        assertTrue(token.transferFrom(holder, alice, 0));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferFromZeroAddressSourceReverts() public {
        // The zero address can never approve, so there is no allowance to spend.
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(address(0), alice, 1);
    }

    function test_approveFromZeroAddressReverts() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(alice, 1);
    }

    function test_transferFromToSelfSpendsAllowanceKeepsBalance() public {
        vm.prank(holder);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        assertTrue(token.transferFrom(holder, holder, 4 ether));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.allowance(holder, bob), 6 ether);
    }

    function test_allowanceSpentExactlyToZeroThenReverts() public {
        vm.prank(holder);
        token.approve(bob, 3);
        vm.startPrank(bob);
        assertTrue(token.transferFrom(holder, alice, 3));
        assertEq(token.allowance(holder, bob), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(holder, alice, 1);
        vm.stopPrank();
    }

    function test_maxMinusOneAllowanceIsDecremented() public {
        // Only exactly type(uint256).max is treated as infinite.
        vm.prank(holder);
        token.approve(bob, type(uint256).max - 1);
        vm.prank(bob);
        token.transferFrom(holder, alice, 1 ether);
        assertEq(token.allowance(holder, bob), type(uint256).max - 1 - 1 ether);
    }

    function test_revokeAllowanceBlocksSpender() public {
        vm.startPrank(holder);
        token.approve(bob, 100);
        token.approve(bob, 0);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(holder, alice, 1);
    }

    function test_failedTransferChangesNothing() public {
        vm.prank(holder);
        token.transfer(alice, 5);
        vm.prank(alice);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (bob, 6)));
        assertFalse(ok);
        assertEq(token.balanceOf(alice), 5);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_plainEtherIsRejected() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_unknownSelectorReverts() public {
        (bool ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferBetweenThirdParties(uint256 funded, uint256 amount) public {
        funded = bound(funded, 0, SUPPLY);
        amount = bound(amount, 0, funded);
        vm.prank(holder);
        token.transfer(alice, funded);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), funded - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(holder), SUPPLY - funded);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(holder), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveAnyAmountIsStoredExactly(address spender, uint256 amount) public {
        spender = address(uint160(bound(uint160(spender), 1, type(uint160).max)));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
