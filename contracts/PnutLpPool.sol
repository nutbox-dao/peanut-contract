pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./Ownable.sol";

interface ERC20Token {
    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract PnutLpPool is Ownable {
    using SafeMath for uint256;

    struct Delegator {
        uint256 pnutLpAmount;          // deposted pnutLp
        uint256 availablePeanuts;   // minted peanuts for user
        uint256 debtRewards;        // rewards debt 
        bool hasDeposited;          // set true when first time deposit
    }

    mapping(address => Delegator) public delegators;
    address[] public delegatorsList;
    uint256 public shareAcc;
    uint256 public totalDepositedPnutLp;
    address public devAddress;
    uint256 public lastRewardBlock;
    uint256 public rewardPerBlock;          // params1:reward per block
    uint256 public endRewardBlock;        // params2:reward pnut before this block

    ERC20Token Pnuts;
    ERC20Token PnutLp;

    event Deposit(address delegator, uint256 amount);
    event Withdraw(address delegator, uint256 amount);
    event WithdrawPeanuts(address delegator, uint256 amount);

    modifier onlyDelegator() {
        require(delegators[msg.sender].hasDeposited, "Account is not a delegator");
        _;
    }

    constructor (address _punts, address _pnutLp) public {
        Pnuts = ERC20Token(_punts);
        PnutLp = ERC20Token(_pnutLp);

        shareAcc = 0;
        totalDepositedPnutLp = 0;
        lastRewardBlock = 0;
        rewardPerBlock = 200000;
        endRewardBlock = block.number.add(10000000);
    }

    // should do this before game start
    function setDevAddress(address dev) 
        public
        onlyOwner
    {
        require(dev != address(0), "Invalid dev address");
        devAddress = dev;
    }

    function deposit(uint256 _amount)
        public
    {
        if (_amount == 0) return;

        // lastRewardBlock == 0 means there is not delegator exist. When first delegator come,
        // we set lastRewardBlock as current block number, then our game starts!
        if (lastRewardBlock == 0) {
            lastRewardBlock = block.number;
        }

        uint256 pnutLpBalance = PnutLp.balanceOf(msg.sender);
        require(_amount <= pnutLpBalance, "ERC20: transfer amount exceeds balance");

        PnutLp.transferFrom(msg.sender, address(this), _amount);

        // Add to delegator list if account hasn't deposited before
        if(!delegators[msg.sender].hasDeposited) {
            delegators[msg.sender].hasDeposited = true;
            delegators[msg.sender].availablePeanuts = 0;
            delegators[msg.sender].pnutLpAmount = 0;
            delegators[msg.sender].debtRewards = 0;
            delegatorsList.push(msg.sender);
        }

        _updateRewardInfo();

        if (delegators[msg.sender].pnutLpAmount > 0) {
            uint256 pending = delegators[msg.sender].pnutLpAmount.mul(shareAcc).div(1e12).sub(delegators[msg.sender].debtRewards);
            if(pending > 0) {
                delegators[msg.sender].availablePeanuts = delegators[msg.sender].availablePeanuts.add(pending);
            }
        }

        delegators[msg.sender].pnutLpAmount = delegators[msg.sender].pnutLpAmount.add(_amount);
        totalDepositedPnutLp = totalDepositedPnutLp.add(_amount);

        delegators[msg.sender].debtRewards = delegators[msg.sender].pnutLpAmount.mul(shareAcc).div(1e12);

        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) 
        public
        onlyDelegator
    {
        if (_amount == 0) return;

        if (delegators[msg.sender].pnutLpAmount == 0) return;

        _updateRewardInfo();

        uint256 pending = delegators[msg.sender].pnutLpAmount.mul(shareAcc).div(1e12).sub(delegators[msg.sender].debtRewards);
        if(pending > 0) {
            delegators[msg.sender].availablePeanuts = delegators[msg.sender].availablePeanuts.add(pending);
        }
        
        uint256 withdrawAmount;
        if (_amount >= delegators[msg.sender].pnutLpAmount)
            withdrawAmount = delegators[msg.sender].pnutLpAmount;
        else
            withdrawAmount = _amount;

        // transfer Pnut-Lp from this to delegator
        PnutLp.transfer(msg.sender, withdrawAmount);
        delegators[msg.sender].pnutLpAmount = delegators[msg.sender].pnutLpAmount.sub(withdrawAmount);
        totalDepositedPnutLp = totalDepositedPnutLp.sub(withdrawAmount);

        delegators[msg.sender].debtRewards = delegators[msg.sender].pnutLpAmount.mul(shareAcc).div(1e12);

        emit Withdraw(msg.sender, withdrawAmount);

        // if canceled , withdrawpeanut
        if(delegators[msg.sender].pnutLpAmount == 0 && delegators[msg.sender].availablePeanuts != 0) {
            Pnuts.transfer(msg.sender, delegators[msg.sender].availablePeanuts);
            delegators[msg.sender].availablePeanuts = 0;
            emit WithdrawPeanuts(msg.sender, delegators[msg.sender].availablePeanuts);
        }
    }
    
    function withdrawPeanuts() 
        public
        onlyDelegator
    {
        // game has not started
        if (lastRewardBlock == 0) return;

        // There are new blocks created after last updating, so append new rewards before withdraw
        if(block.number > lastRewardBlock) {
            _updateRewardInfo();
        }

        uint256 pending = delegators[msg.sender].pnutLpAmount.mul(shareAcc).div(1e12).sub(delegators[msg.sender].debtRewards);
        if(pending > 0) {
            delegators[msg.sender].availablePeanuts = delegators[msg.sender].availablePeanuts.add(pending);
        }

        Pnuts.transfer(msg.sender, delegators[msg.sender].availablePeanuts);

        delegators[msg.sender].debtRewards = delegators[msg.sender].pnutLpAmount.mul(shareAcc).div(1e12);

        emit WithdrawPeanuts(msg.sender, delegators[msg.sender].availablePeanuts);

        delegators[msg.sender].availablePeanuts = 0;
    }
    
    // pending peanuts >= delegator.availablePeanuts
    function getPendingPeanuts() public view returns (uint256) {
        // game has not started
        if (lastRewardBlock == 0) return 0;

        uint256 currentBlock = block.number;

        // our lastRewardBlock isn't up to date, as the result, the availablePeanuts isn't
        // the right amount that delegator can award
        if (currentBlock > lastRewardBlock && totalDepositedPnutLp != 0) {
            uint256 _shareAcc = shareAcc;
            uint256 unmintedPeanuts = _calculateReward();
            _shareAcc = _shareAcc.add(unmintedPeanuts.mul(1e12).div(totalDepositedPnutLp));
            uint256 pending = delegators[msg.sender].pnutLpAmount.mul(_shareAcc).div(1e12).sub(delegators[msg.sender].debtRewards);
            return delegators[msg.sender].availablePeanuts.add(pending);
        } else {
            return delegators[msg.sender].availablePeanuts;
        }
    }

    function _updateRewardInfo() internal {

        // game has not started
        if (lastRewardBlock == 0) return;

        uint256 currentBlock = block.number;

        if (currentBlock <= lastRewardBlock) return;

        uint256 unmintedPeanuts = _calculateReward();

        // whenever game being stopped, reset shareAcc
        if (totalDepositedPnutLp == 0){
            shareAcc = shareAcc.add(unmintedPeanuts.mul(1e12).div(1));
        }else{
            shareAcc = shareAcc.add(unmintedPeanuts.mul(1e12).div(totalDepositedPnutLp));
        }

        lastRewardBlock = block.number;
    }

    function _calculateReward()  internal view returns (uint256) {
        uint256 currentBlock = block.number;
        if(currentBlock <= lastRewardBlock)
            return 0;
        
        if(lastRewardBlock < endRewardBlock){
            if(currentBlock < endRewardBlock){
                return rewardPerBlock.mul(currentBlock.sub(lastRewardBlock));
            }else{
                return rewardPerBlock.mul(endRewardBlock.sub(lastRewardBlock));
            }
        }else{
            return 0;
        }
    }

    function getDelegatorListLength() public view returns(uint256) {
        return delegatorsList.length;
    }

    function updateParams(uint256 _rewardPerBlock, uint256 _totalRewardBlock) 
        public
        onlyOwner
    {
        // settle reward of last era
        _updateRewardInfo();
        rewardPerBlock = _rewardPerBlock;
        endRewardBlock = block.number.add(_totalRewardBlock);
    }

    function withdrawBalanceToDev(uint256 _amount) 
        public
        onlyOwner
    {
        uint256 balance = Pnuts.balanceOf(address(this));
        if (balance > _amount){
            Pnuts.transfer(devAddress, _amount);
        }else{
            Pnuts.transfer(devAddress, balance);
        }
    }
}