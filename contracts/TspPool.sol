pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./Ownable.sol";

interface ERC20Token {
    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface PeanutsPool {
    function withdrawPeanuts() external;
    function getPendingPeanuts() external view returns (uint256);
}

contract TspPooling is Ownable {
    using SafeMath for uint256;

    struct Delegator {
        uint256 tspAmount;          // deposted tsp
        uint256 lptokenAmount;      // deposted tsp
        uint256 availablePeanuts;   // minted peanuts for user
        uint256 debtRewards;        // rewards debt 
        bool hasDeposited;          // set true when first time deposit
    }

    mapping(address => Delegator) public delegators;
    address[] public delegatorsList;
    uint256 public shareAcc;
    uint256 public totalDepositedTSP;
    address public pairAddress;
    uint256 public lastRewardBlock;

    ERC20Token Pnuts;
    ERC20Token Tsp;
    PeanutsPool PnutPool;

    event DepositTSP(address delegator, uint256 amount);
    event WithdrawTSP(address delegator, uint256 amount);
    event WithdrawPeanuts(address delegator, uint256 amount);

    modifier onlyDelegator() {
        require(delegators[msg.sender].hasDeposited, "Account is not a delegator");
        _;
    }

    constructor (address _punts, address _pnutPool, address _tsp) public {
        Pnuts = PnutsToken(_punts);
        Tsp = NutboxTsp(_tsp);
        PnutPool = PeanutsPool(_pnutPool);

        shareAcc = 0;
        totalDepositedTSP = 0;
        lastRewardBlock = 0;
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

        uint256 tspBalance = Tsp.balanceOf(msg.sender);
        require(_amount <= tspBalance, "ERC20: transfer amount exceeds balance");

        Tsp.transferFrom(msg.sender, address(this), _amount);

        // Add to delegator list if account hasn't deposited before
        if(!delegators[msg.sender].hasDeposited) {
            delegators[msg.sender].hasDeposited = true;
            delegators[msg.sender].availablePeanuts = 0;
            delegators[msg.sender].tspAmount = 0;
            delegators[msg.sender].debtRewards = 0;
            delegatorsList.push(msg.sender);
        }

        _updateRewardInfo();

        if (delegators[msg.sender].tspAmount > 0) {
            uint256 pending = delegators[msg.sender].tspAmount.mul(shareAcc).div(1e12).sub(delegators[msg.sender].debtRewards);
            if(pending > 0) {
                delegators[msg.sender].availablePeanuts = delegators[msg.sender].availablePeanuts.add(pending);
            }
        }

        delegators[msg.sender].tspAmount = delegators[msg.sender].tspAmount.add(_amount);
        totalDepositedTSP = totalDepositedTSP.add(_amount);

        delegators[msg.sender].debtRewards = delegators[msg.sender].tspAmount.mul(shareAcc).div(1e12);

        emit DepositTSP(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) 
        public
        onlyDelegator
    {
        if (_amount == 0) return;

        if (delegators[delegator].tspAmount == 0) return;

        _updateRewardInfo();

        uint256 pending = delegators[msg.sender].tspAmount.mul(shareAcc).div(1e12).sub(delegators[delegator].debtRewards);
        if(pending > 0) {
            delegators[delegator].availablePeanuts = delegators[delegator].availablePeanuts.add(pending);
        }
        
        uint256 withdrawAmount;
        if (_amount >= delegators[msg.sender].tspAmount)
            withdrawAmount = delegators[msg.sender].tspAmount;
        else
            withdrawAmount = _amount;

        // transfer TSP from this to delegator
        TSP.transfer(msg.sender, withdrawAmount);
        delegators[msg.sender].tspAmount = delegators[msg.sender].tspAmount.sub(withdrawAmount);
        totalDepositedTSP = totalDepositedTSP.sub(withdrawAmount);

        delegators[msg.sender].debtRewards = delegators[msg.sender].tspAmount.mul(shareAcc).div(1e12);

        emit WithdrawTSP(msg.sender, withdrawAmount);
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

        uint256 pending = delegators[msg.sender].tspAmount.mul(shareAcc).div(1e12).sub(delegators[msg.sender].debtRewards);
        if(pending > 0) {
            delegators[msg.sender].availablePeanuts = delegators[msg.sender].availablePeanuts.add(pending);
        }

        Pnuts.transfer(msg.sender, delegators[msg.sender].availablePeanuts);

        delegators[msg.sender].debtRewards = delegators[msg.sender].tspAmount.mul(shareAcc).div(1e12);

        emit WithdrawPeanuts(msg.sender, delegators[msg.sender].availablePeanuts);

        delegators[msg.sender].availablePeanuts = 0;
    }

    // TODO: transfer peanuts to dev
    function rewardToDev() public onlyOwner {

    }
    
    // pending peanuts >= delegator.availablePeanuts
    function getPendingPeanuts() public view returns (uint256) {
        // game has not started
        if (lastRewardBlock == 0) return 0;

        uint256 currentBlock = block.number;

        // our lastRewardBlock isn't up to date, as the result, the availablePeanuts isn't
        // the right amount that delegator can award
        if (currentBlock > lastRewardBlock) {
            uint256 _shareAcc = shareAcc;
            uint256 unmintedPeanuts = _calculateReward();
            _shareAcc = _shareAcc.add(unmintedPeanuts.mul(1e12).div(totalDepositedTSP));
            uint256 pending = delegators[msg.sender].tspAmount.mul(_shareAcc).div(1e12).sub(delegators[msg.sender].debtRewards);
            return delegators[msg.sender].availablePeanuts.add(pending);
        } else {
            return delegators[msg.sender].availablePeanuts;
        }
    }

    function getTotalPendingPeanuts() public view returns (uint256) {
        // game has not started
        if (lastRewardBlock == 0) return 0;

        uint256 currentBlock = block.number;
        uint256 totalRewardPeanuts = Pnuts.balanceOf(address(this));

        // our lastRewardBlock isn't up to date, as the result, the availablePeanuts isn't
        // the right amount that delegator can award
        if (currentBlock > lastRewardBlock) {
            uint256 unmintedPeanuts = _calculateReward();
            return totalRewardPeanuts.add(unmintedPeanuts).add(unmintedPeanuts.div(10));
        } else {
            return totalRewardPeanuts;
        }
    }

    function getDelegatorListLength() public view returns(uint256) {
        return delegatorsList.length;
    }

    function _updateRewardInfo() internal {
        uint256 peanutsReadyToMinted = 0;

        // calculate latest reward peanuts
        peanutsReadyToMinted = _calculateReward();

        PnutPool.withdrawPeanuts();

        shareAcc = shareAcc.add(peanutsReadyToMinted.mul(1e12).div(totalDepositedTSP));
    }

    // TODO: should dynamic calculate rewards
    // rewards belong to delegaters should be:
    //     Peanuts.balanceOf(address(this)).mult(totalDelegatedTSP.div(Tsp.totalSupply()))
    function _calculateReward() internal view returns (uint256) {
        return PnutPool.getPendingPeanuts();
    }
}