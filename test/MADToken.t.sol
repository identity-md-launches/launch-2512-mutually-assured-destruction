// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Deploys the token from a known deployer so tests can reason about who holds the supply.
contract Deployer {
    function deploy() external returns (MADToken) {
        return new MADToken();
    }
}

contract MADTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    MADToken internal token;
    Deployer internal deployer;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        deployer = new Deployer();
        token = deployer.deploy();
    }

    // ------------------------------------------------------------------
    // Metadata and supply
    // ------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), token.name());
        assertEq(token.TOKEN_SYMBOL(), token.symbol());
        assertEq(uint256(token.DECIMALS()), uint256(token.decimals()));
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
    }

    function test_wholeSupplyMintedToDeployer() public view {
        assertEq(token.balanceOf(address(deployer)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsTransferAndSupplyMinted() public {
        // Recompute the address the next deployment will land at so the expected events match.
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectEmit(predicted);
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        vm.expectEmit(predicted);
        emit MADToken.SupplyMinted(address(this), SUPPLY);
        MADToken fresh = new MADToken();
        assertEq(address(fresh), predicted);
        assertEq(fresh.balanceOf(address(this)), SUPPLY);
    }

    function test_eachDeploymentMintsToItsOwnDeployer() public {
        vm.prank(alice);
        MADToken byAlice = new MADToken();
        assertEq(byAlice.balanceOf(alice), SUPPLY);
        assertEq(byAlice.totalSupply(), SUPPLY);
        // The original deployment is untouched.
        assertEq(token.balanceOf(address(deployer)), SUPPLY);
    }

    // ------------------------------------------------------------------
    // No mint, no admin surface
    // ------------------------------------------------------------------

    function test_noMintFunctionExists() public {
        string[6] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setMinter(address)",
            "initialize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, type(uint128).max);
            vm.prank(address(deployer));
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(alice), 0, signatures[i]);
        }
    }

    function test_noAdminFunctionExists() public {
        string[12] memory signatures = [
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "freeze(address)",
            "setBlacklist(address,bool)",
            "burnFrom(address,uint256)",
            "burn(uint256)",
            "seize(address)",
            "upgradeTo(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, true);
            vm.prank(address(deployer));
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
    }

    function test_deployerHasNoPowerOverHolders() public {
        _fund(alice, 1_000 ether);

        // The deployer cannot move Alice's balance without an allowance...
        vm.prank(address(deployer));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(deployer), 0, 1)
        );
        token.transferFrom(alice, address(deployer), 1);

        // ...and Alice can still transfer freely.
        vm.prank(alice);
        assertTrue(token.transfer(bob, 400 ether));
        assertEq(token.balanceOf(alice), 600 ether);
        assertEq(token.balanceOf(bob), 400 ether);
    }

    function test_runtimeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    function test_runtimeFitsEip170() public view {
        assertLe(address(token).code.length, 24_576);
    }

    // ------------------------------------------------------------------
    // Transfers: success
    // ------------------------------------------------------------------

    function test_transferMovesExactAmount() public {
        vm.prank(address(deployer));
        vm.expectEmit(address(token));
        emit IERC20.Transfer(address(deployer), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.balanceOf(address(deployer)), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(address(deployer));
        assertTrue(token.transfer(alice, 0));
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        _fund(alice, 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(alice, 10 ether));
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_transferWholeBalance() public {
        _fund(alice, 5 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 5 ether));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 5 ether);
    }

    function test_launchFlowsArriveWhole() public {
        // The factory (deployer) pays out 10% to a distributor, which pays a claimant: both whole.
        uint256 swarm = SUPPLY / 10;
        vm.prank(address(deployer));
        assertTrue(token.transfer(alice, swarm));
        assertEq(token.balanceOf(alice), swarm);
        vm.prank(alice);
        assertTrue(token.transfer(bob, swarm));
        assertEq(token.balanceOf(bob), swarm);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ------------------------------------------------------------------
    // Transfers: failure
    // ------------------------------------------------------------------

    function test_transferRevertsOnInsufficientBalance() public {
        _fund(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1 ether, 1 ether + 1)
        );
        token.transfer(bob, 1 ether + 1);
    }

    function test_transferFromEmptyAccountReverts() public {
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, carol, 0, 1));
        token.transfer(bob, 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.prank(address(deployer));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    // ------------------------------------------------------------------
    // Allowances: success
    // ------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.prank(alice);
        vm.expectEmit(address(token));
        emit IERC20.Approval(alice, bob, 77);
        assertTrue(token.approve(bob, 77));
        assertEq(token.allowance(alice, bob), 77);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(alice);
        token.approve(bob, 77);
        token.approve(bob, 5);
        vm.stopPrank();
        assertEq(token.allowance(alice, bob), 5);
    }

    function test_transferFromSpendsAllowance() public {
        _fund(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 60 ether);

        vm.prank(bob);
        vm.expectEmit(address(token));
        emit IERC20.Transfer(alice, carol, 40 ether);
        assertTrue(token.transferFrom(alice, carol, 40 ether));

        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.balanceOf(carol), 40 ether);
        assertEq(token.allowance(alice, bob), 20 ether);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        _fund(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 30 ether));
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(carol), 30 ether);
    }

    // ------------------------------------------------------------------
    // Allowances: failure
    // ------------------------------------------------------------------

    function test_transferFromWithoutAllowanceReverts() public {
        _fund(alice, 100 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1 ether));
        token.transferFrom(alice, carol, 1 ether);
    }

    function test_transferFromAboveAllowanceReverts() public {
        _fund(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 10 ether, 10 ether + 1)
        );
        token.transferFrom(alice, carol, 10 ether + 1);
    }

    function test_transferFromAboveBalanceRevertsEvenWithAllowance() public {
        _fund(alice, 5 ether);
        vm.prank(alice);
        token.approve(bob, 100 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        token.transferFrom(alice, carol, 6 ether);
    }

    function test_approveZeroSpenderReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromToZeroAddressReverts() public {
        _fund(alice, 5 ether);
        vm.prank(alice);
        token.approve(bob, 5 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(alice, address(0), 1 ether);
    }

    // ------------------------------------------------------------------
    // Fuzz: conservation of supply and balances
    // ------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(deployer));
        amount = bound(amount, 0, SUPPLY);
        vm.prank(address(deployer));
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(address(deployer)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 funded, uint256 attempt) public {
        funded = bound(funded, 0, SUPPLY - 1);
        attempt = bound(attempt, funded + 1, SUPPLY);
        _fund(alice, funded);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, attempt));
        token.transfer(bob, attempt);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowance_, uint256 amount) public {
        allowance_ = bound(allowance_, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY);
        _fund(alice, SUPPLY);
        vm.prank(alice);
        token.approve(bob, allowance_);

        vm.prank(bob);
        if (amount > allowance_) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, allowance_, amount)
            );
            token.transferFrom(alice, carol, amount);
        } else {
            assertTrue(token.transferFrom(alice, carol, amount));
            assertEq(token.balanceOf(carol), amount);
            assertEq(token.allowance(alice, bob), allowance_ - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_roundTripLeavesBalancesUnchanged(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        _fund(alice, SUPPLY);
        vm.prank(alice);
        token.transfer(bob, amount);
        vm.prank(bob);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _fund(address to, uint256 amount) internal {
        vm.prank(address(deployer));
        require(token.transfer(to, amount), "fund failed");
    }
}
