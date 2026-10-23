// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {MADToken} from "../src/MADToken.sol";

/// @title Deploy script for MADToken
/// @notice Reviewable reference deployment. On an IdentityMD launch the ProjectFactory deploys the
///         token from its creation code and this script is not used; it exists so the deployment
///         can be read, reproduced locally and tested. It takes no configuration: the token has no
///         constructor arguments, and whoever broadcasts the transaction receives the supply.
contract DeployMADToken is Script {
    /// @notice Deploys the token. Separated from `run()` so tests can call it directly without
    ///         touching the environment or the broadcaster.
    function deploy() public returns (MADToken token) {
        token = new MADToken();
    }

    /// @notice Broadcast entry point. Uses the sender forge was given on the command line.
    function run() external returns (MADToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
