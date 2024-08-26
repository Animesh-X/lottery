// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffleTest is CodeConstants, Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() public {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;
    }

    function testRaffleInialtizesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    // function testEnteringRaffleEmitsEvent() public {
    //     // vm.prank(PLAYER);
    //     // vm.expectEmit(true, false, false, false, address(raffle));
    //     // emit RaffleEntered(PLAYER);
    //     // raffle.enterRaffle{value: entranceFee}();
    //     assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);

    //     vm.prank(PLAYER);
    //     vm.expectEmit(true, false, false, false, address(raffle));
    //     emit RaffleEntered(PLAYER);
    //     raffle.enterRaffle{value: entranceFee}();
    // }
    function testEmitsEventOnEntrance() public {
        // Arrange
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        vm.prank(PLAYER);

        // Act / Assert
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // warp - sets the block timestamp
        vm.warp(block.timestamp + interval + 1);
        // roll - change the block number
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    // Check upKeep

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        // warp - sets the block timestamp
        vm.warp(block.timestamp + interval + 1);
        // roll - change the block number
        vm.roll(block.number + 1);

        // Act / Assert
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfItRaffleIsntOpen() public {
        // Arrange
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // warp - sets the block timestamp
        vm.warp(block.timestamp + interval + 1);
        // roll - change the block number
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act / Assert
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);

    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed() public {
        // Arrange
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        vm.prank(PLAYER);
        // warp - sets the block timestamp
        vm.warp(block.timestamp + interval + 1);

        // Act / Assert
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        // Arrange
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // warp - sets the block timestamp
        vm.warp(block.timestamp + interval + 1);
        // roll - change the block number
        vm.roll(block.number + 1);

        // Act / Assert
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    // Check performUpkeep

    function testPerformUpkeepCanRunOnlyIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // warp - sets the block timestamp
        vm.warp(block.timestamp + interval + 1);
        // roll - change the block number
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayers = numPlayers + 1;

        // Act / Assert

        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );
        raffle.performUpkeep("");
    }

    modifier raffleEntered {
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // warp - sets the block timestamp
        vm.warp(block.timestamp + interval + 1);
        // roll - change the block number
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered {        

        // Act 
        vm.recordLogs();
        // Whatever events are emitted by the performUpkeep function will be logged in an array
        raffle.performUpkeep("");
        // get all the login in entries array
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // VmLogs memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        // bytes32 requestId = abi.decode(entries[1].data, (bytes32));

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    // Fulfill Random Words

    modifier skipFork() {
        if(block.chainid != LOCAL_CHAIN_ID){
            return;
        }
        _;
    }

    function testFullfillRandomWordsCanBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered skipFork {
        // Arrange / Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));

    }

    function testFulfillrandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered skipFork {
        // Arrange
        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for(uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++){
            address newPlayer = address(uint160(i));
            // sets up an prank and give some ether
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimestamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        // Whatever events are emitted by the performUpkeep function will be logged in an array
        raffle.performUpkeep("");
        // get all the login in entries array
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // VmLogs memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimestamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }

}
