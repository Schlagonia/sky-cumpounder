// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {SkyCumpounder} from "../src/SkyCumpounder.sol";
import {console} from "forge-std/console.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";

contract Deploy is Script {

    address public lockstakeEngine = 0xCe01C90dE7FD1bcFa39e237FE6D8D9F569e8A6a3;
    address public farm = 0x38E4254bD82ED5Ee97CD1C4278FAae748d998865;

    address public keeper = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address public accountant = 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69;
    address public sms = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    function run() public {

        deployOracle();
        return;
        
        vm.startBroadcast();

        SkyCumpounder skyCumpounder = new SkyCumpounder(
            lockstakeEngine,
            farm
        );

        console.log("SkyCumpounder deployed to:", address(skyCumpounder));

        IStrategyInterface strategy = IStrategyInterface(address(skyCumpounder));

        strategy.setKeeper(keeper);
        strategy.setPerformanceFeeRecipient(accountant);
        strategy.setEmergencyAdmin(sms);
        strategy.setPerformanceFee(0);
        strategy.setPendingManagement(sms);

        vm.stopBroadcast();
    }


    function deployOracle() public {
        vm.startBroadcast();

        StrategyAprOracle oracle = new StrategyAprOracle();

        console.log("StrategyAprOracle deployed to:", address(oracle));

        vm.stopBroadcast();
    }
}