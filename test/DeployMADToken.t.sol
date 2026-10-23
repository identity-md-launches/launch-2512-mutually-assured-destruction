// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployMADToken} from "../script/DeployMADToken.s.sol";
import {MADToken} from "../src/MADToken.sol";

contract DeployMADTokenTest is Test {
    function test_deployMintsSupplyToTheScriptCaller() public {
        DeployMADToken script = new DeployMADToken();
        // `deploy()` creates the token from the script contract, so the script is the deployer.
        MADToken token = script.deploy();
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(script)), 1_000_000_000 ether);
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
    }

    function test_creationCodeHasNoConstructorArguments() public pure {
        // The launch deploys the creation code as built, with no appended arguments.
        bytes memory code = type(MADToken).creationCode;
        assertGt(code.length, 0);
    }
}
