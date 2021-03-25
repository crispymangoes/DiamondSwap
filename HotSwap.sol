//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//import "@openzeppelin/contracts/access/Ownable.sol";
//import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
/*
* Want to use ALL of token0 in the swap so use getAmountsOut in RouterO2
*/

interface DIAtoken {
        function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
        function approve(address spender, uint256 amount) external returns (bool);
    }

contract HotSwap is Ownable {

    event SwapCompleted(uint256 swapId, uint256 sent, uint256 recieved, uint256 blockStart, uint256 blockEnd);
    event userAdded(address user, uint256 userCount, uint256 swapSize);
    struct swapLogistics {
        uint256 token0Sent; // Number of token0 sent to swap ( allows contract to get exchnage rate )
        uint256 token1Recieved; // Number of token1 recived from swap
        uint256 blockStart; // Block number when the contract recieved first user deposit to swap
        uint256 blockEnd; // Block number when the swap took place
        uint256 gasRefundToLastUser; // Used to store the balance of ETH, that the last user that sent the contract is owed
        // Ie if uniswap used 5,0000 gas, with 10 people in the swap, then the last person should get refunded 4,500 gas
        address[] usersInSwap;
    }

    struct userLogistics {
        uint256 swapId; // The swap the user is currently apart of
        uint256 balance; // Balance of how much of token0 user sent to smart contract ( with 1% dev fee removed which is calculated when user deposits )
        // As long as balance is not zero user has a withdraw to make
    }
    

    bool public Locked;
    uint16 public userCount; 
    uint256 public currentSwapId;
    uint256 public swapSize; 
    uint256 public devFund;
    uint256 public maxSwapSize = 100;
    mapping (uint256 => swapLogistics) public swapLedger; // Map a swapId integer to the corresponding swapLogistics
    mapping ( address => userLogistics) public userLedger; // Map user address to the corresponding userLogistics
    address public uniswapV2_ADDR = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IUniswapV2Router02 public UNIV2 = IUniswapV2Router02(uniswapV2_ADDR);
    
    address public DAI_CONTRACT_ADDR = 0xaD6D458402F60fD3Bd25163575031ACDce07538D; // For Ropsten
    DIAtoken DAI = DIAtoken(DAI_CONTRACT_ADDR);

    constructor(uint256 _swapSize) public {
        // TODO: Needs more basic logic to handle ETH, and any other ERC20 token
        userCount = 0; // Start at 15 so that when the first user joins it rolls over to 0
        Locked = false;
        currentSwapId = 0;
        swapSize = _swapSize;
        swapLedger[currentSwapId].blockStart = block.number;
        devFund = 0;
    }
    
    fallback() payable external {} // allows incoming ether
    receive() payable external {}

    function getUserApproval(uint tokenAmountIn) public {
        tokenAmountIn = 50 * 10 ** 18;
        require(DAI.approve(address(this), tokenAmountIn), 'approve failed.');

    }
    function depositFunds(uint tokenAmountIn) public {
        //require(!Locked, "Hot Swap: Cannot join a Hot Swap in progress");
        //require(userCount < swapSize, "Hot Swap: Hot Swap full");
        //require(userLedger[msg.sender].balance == 0, "Hot Swap: Make withdrawal before entering new Hot Swap");
        //require(msg.value == 0, "Hot Swap: You can only submit DAI to this contract");
        tokenAmountIn = 50 * 10 ** 18;
        require(DAI.transferFrom(msg.sender, address(this), tokenAmountIn), 'transferFrom failed.');

        //userLedger[msg.sender].balance = tokenAmountIn; // Whatever they transfered in
        //swapLedger[currentSwapId].token0Sent = swapLedger[currentSwapId].token0Sent + tokenAmountIn;
        //userLedger[msg.sender].swapId = currentSwapId;
        //swapLedger[currentSwapId].usersInSwap.push(msg.sender);
        //userCount++; 
        /*
        if (userCount >= swapSize) {
            if (makeSwap()) {
                userCount = 0;
            }
            else { 
                // Swap failed so I am not sure what the best way to handle this is
                // Or probs better to just return users funds, not a great experience for them it greatly simplifies contract logic and security
            }
        }
        */

    }

    function withdrawFunds(address payable _address) payable public {
        require(userLedger[_address].swapId != currentSwapId, "Hot Swap: Cannot withdraw from current swap"); // This will stop users from withdrawing their token0 if they change their mind so I may want to change this functionality later
        require(userLedger[_address].balance > 0, "Hot Swap: Cannot withdraw with a zero balance");
        // make sure to do the send transaction last, ie change usre balance to 0 before sending anything

        // The very last user in swapLogistics[currentSwapId].usersInSwap needs to be refunded (uniswap fee - their part in the fee)
        uint256 indexOfLastUser = swapSize - 1;
        if ( msg.sender == swapLedger[userLedger[msg.sender].swapId].usersInSwap[indexOfLastUser]){
            userLedger[msg.sender].balance = userLedger[msg.sender].balance + swapLedger[userLedger[msg.sender].swapId].gasRefundToLastUser; // Refund the last user the gas amount
        }
        uint balToSend = userLedger[msg.sender].balance * (swapLedger[userLedger[msg.sender].swapId].token1Recieved / swapLedger[userLedger[msg.sender].swapId].token0Sent);
        userLedger[msg.sender].balance = 0;
        require(_address.send(balToSend));
    }

    function makeSwap() internal returns (bool){
        // if swap was successful make sure to return true otherwise return false
        // after making swap do a for loop through swapLogistics[currentSwapId].usersInSwap[0 -> userCount]; and update balances based off uniswap fee
        // might also make sense to not worry about the dev fee until here that way dev fee isn't taken until swap happens which allows for the code to be modified in the future to allow people to withdraw before it swaps and move funds to different hot swaps
        // only update user balances after swap is successfull

        /*
        TODO: Add in logic to use uniswap price oracle, and set slippage envelope
        */

        uint256 gasStart = gasleft();

        /*
        // Make the swap,
        // amountOutMin must be retrieved from an oracle of some kind
        uint amountOutMin = 1; // Needs to be grabbed from a price oracle
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = IUniswapV2Router02.WETH();
        swapLedger[currentSwapId].token1Recieved = IUniswapV2Router02.swapExactTokensForETH(swapLedger[currentSwapId].token0Sent, amountOutMin, path, msg.sender, block.timestamp);
        */


        uint256 gasUsed = gasStart - gasleft();
        uint256 gasSplitPerUser = gasUsed/swapSize;
        swapLedger[currentSwapId].gasRefundToLastUser = gasUsed;
        /*
        TODO: If swap fails refund all users their balance
        call refundAll(gasSplitPerUser)
        Also emit a new event called swap failed that comes with an error message
        */

        // if swap is successfull
        // Subtract dev fee, and gasSplitPerUser fee from all ledger entries in this swap
        address user;
        uint256 _devFee;
        for ( uint i; i < swapSize; i++){
            user = swapLedger[currentSwapId].usersInSwap[i];
            _devFee = userLedger[user].balance/100;
            devFund = devFund + _devFee;
            userLedger[user].balance = userLedger[user].balance - ( _devFee + gasSplitPerUser ); // Remove the dev fee and the gas splt per user fee
        }

        swapLedger[currentSwapId].blockEnd = block.number;
        swapLedger[currentSwapId].token0Sent = 0;
        swapLedger[currentSwapId].token1Recieved = 0;
        emit SwapCompleted(currentSwapId, swapLedger[currentSwapId].token0Sent, swapLedger[currentSwapId].token1Recieved, swapLedger[currentSwapId].blockStart, swapLedger[currentSwapId].blockEnd);
        currentSwapId++;
        //TODO refund the msg.sender any remaining gas
    }
    /*
    function refundAll(uint _gasSplitPerUser) internal {
        // Refunds all users their remaining balances if a swap fails
        for ( uint i; i < swapSize; i++){
            address user = swapLedger[currentSwapId].usersInSwap[i];
            uint256 bal = userLedger[user].balance - _gasSplitPerUser;
            if ( i == (swapSize - 1)){
                // make sure to send this user
                bal = bal + swapLedger[currentSwapId].gasRefundToLastUser;
            }
            require(msg.sender.send(bal));
        }
    }
    */
    
    function changeMaxSwapSize(uint256 _maxSwapSize) external onlyOwner {
        require(_maxSwapSize > 1, "Hot Swap: Max Swap Size must be atleast 2");
        maxSwapSize = _maxSwapSize;
    }
    
    function changeSwapSize(uint256 _swapSize) external onlyOwner {
        require(_swapSize > 1, "Hot Swap: Swap Size must be atleast 2");
        require(_swapSize <= maxSwapSize, "Hot Swap: Swap Size must be less than or equal to maxSwapSize"); // Doing this so that a DAO can vote to change this at a later date
        swapSize = _swapSize;
    }
    
    function withdrawDevFund(address payable _address) payable public onlyOwner {
        require(devFund > 0, "Hot Swap: devFuns must be greater than zero to withdraw");
        devFund = 0; // might want this after the transfer
        require(_address.send(devFund)); 
        }

    /*function swapHistory(uint _swapId)external returns(swapLogistics swapData){
        // might need to require its greater than or equal to zero
        require(_swapId <= currentSwapId, "Hot Swap: Cannot get swap ledger, entry does not exist");
        return swapLedger[_swapId];
    }*/
}
