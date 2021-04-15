pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./Ownable.sol";

interface ERC20Token {
    function transfer(address _to, uint256 _value) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

interface PeanutsPool {
    function withdrawPeanuts() external;

    function getPendingPeanuts() external view returns (uint256);
}

contract TsteemPool is Ownable {
    using SafeMath for uint256;
    struct Delegator {
        uint256 tsteemAmount; // deposted tsteem
        uint256 availablePeanuts; // minted peanuts for user
        uint256 debtRewards; // rewards debt
        bool hasDeposited; // set true when first time deposit
    }
    mapping(address => Delegator) public delegators;
    address[] public delegatorsList;
    uint256 public shareAcc;
    uint256 public totalDepositedTSTEEM;
    address public devAddress;
    uint256 public lastRewardBlock;

    ERC20Token Pnuts;
    ERC20Token Tsteem;
    PeanutsPool PnutPool;

    event DepositTSTEEM(address delegator, uint256 amount);
    event WithdrawTSTEEM(address delegator, uint256 amount);
    event WithdrawPeanuts(address delegator, uint256 amount);

    modifier onlyDelegator() {
        require(
            delegators[msg.sender].hasDeposited,
            "Account is not a delegator"
        );
        _;
    }

    constructor(
        address _punts,
        address _pnutPool,
        address _tsteem,
        address _devAddress
    ) public {
        Pnuts = ERC20Token(_punts);
        Tsteem = ERC20Token(_tsteem);
        PnutPool = PeanutsPool(_pnutPool);

        devAddress = _devAddress;
        shareAcc = 0;
        totalDepositedTSTEEM = 0;
        lastRewardBlock = 0;
    }

    // should do this before game start
    function setDevAddress(address dev) public onlyOwner {
        require(dev != address(0), "Invalid dev address");
        devAddress = dev;
    }

    function deposit(uint256 _amount) public {
        if (_amount == 0) return;

        // totalDepositedTSTEEM == 0 means there is not delegator exist. When first delegator come,
        // we set lastRewardBlock as current block number, then our game starts!
        // and reward before this moment shoud be sent to dev
        if (totalDepositedTSTEEM == 0) {
            PnutPool.withdrawPeanuts();
            Pnuts.transfer(devAddress, Pnuts.balanceOf(address(this)));
            lastRewardBlock = block.number;
        }

        uint256 tsteemBalance = Tsteem.balanceOf(msg.sender);
        require(
            _amount <= tsteemBalance,
            "ERC20: transfer amount exceeds balance"
        );

        Tsteem.transferFrom(msg.sender, address(this), _amount);

        // Add to delegator list if account hasn't deposited before
        if (!delegators[msg.sender].hasDeposited) {
            delegators[msg.sender].hasDeposited = true;
            delegators[msg.sender].availablePeanuts = 0;
            delegators[msg.sender].tsteemAmount = 0;
            delegators[msg.sender].debtRewards = 0;
            delegatorsList.push(msg.sender);
        }

        _updateRewardInfo();

        if (delegators[msg.sender].tsteemAmount > 0) {
            uint256 pending =
                delegators[msg.sender].tsteemAmount.mul(shareAcc).div(1e12).sub(
                    delegators[msg.sender].debtRewards
                );
            if (pending > 0) {
                delegators[msg.sender].availablePeanuts = delegators[msg.sender]
                    .availablePeanuts
                    .add(pending);
            }
        }

        delegators[msg.sender].tsteemAmount = delegators[msg.sender]
            .tsteemAmount
            .add(_amount);
        totalDepositedTSTEEM = totalDepositedTSTEEM.add(_amount);

        delegators[msg.sender].debtRewards = delegators[msg.sender]
            .tsteemAmount
            .mul(shareAcc)
            .div(1e12);

        emit DepositTSTEEM(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public onlyDelegator {
        if (_amount == 0) return;

        if (delegators[msg.sender].tsteemAmount == 0) return;

        _updateRewardInfo();

        uint256 pending =
            delegators[msg.sender].tsteemAmount.mul(shareAcc).div(1e12).sub(
                delegators[msg.sender].debtRewards
            );
        if (pending > 0) {
            delegators[msg.sender].availablePeanuts = delegators[msg.sender]
                .availablePeanuts
                .add(pending);
        }

        uint256 withdrawAmount;
        if (_amount >= delegators[msg.sender].tsteemAmount)
            withdrawAmount = delegators[msg.sender].tsteemAmount;
        else withdrawAmount = _amount;

        // transfer TSTEEM from this to delegator
        Tsteem.transfer(msg.sender, withdrawAmount);
        delegators[msg.sender].tsteemAmount = delegators[msg.sender]
            .tsteemAmount
            .sub(withdrawAmount);
        totalDepositedTSTEEM = totalDepositedTSTEEM.sub(withdrawAmount);

        // now game stopped, reset contract status
        if (totalDepositedTSTEEM == 0) _resetStatus();

        delegators[msg.sender].debtRewards = delegators[msg.sender]
            .tsteemAmount
            .mul(shareAcc)
            .div(1e12);

        // auto withdraw peanuts when he undeposite
        if (delegators[msg.sender].tsteemAmount == 0) {
            Pnuts.transfer(msg.sender, delegators[msg.sender].availablePeanuts);
            delegators[msg.sender].availablePeanuts = 0;
            emit WithdrawPeanuts(
                msg.sender,
                delegators[msg.sender].availablePeanuts
            );
        }
        emit WithdrawTSTEEM(msg.sender, withdrawAmount);
    }

    function withdrawPeanuts() public onlyDelegator {
        // game has not started
        if (lastRewardBlock == 0) return;

        // There are new blocks created after last updating, so append new rewards before withdraw
        if (block.number > lastRewardBlock) {
            _updateRewardInfo();
        }

        uint256 pending =
            delegators[msg.sender].tsteemAmount.mul(shareAcc).div(1e12).sub(
                delegators[msg.sender].debtRewards
            );
        if (pending > 0) {
            delegators[msg.sender].availablePeanuts = delegators[msg.sender]
                .availablePeanuts
                .add(pending);
        }

        Pnuts.transfer(msg.sender, delegators[msg.sender].availablePeanuts);

        delegators[msg.sender].debtRewards = delegators[msg.sender]
            .tsteemAmount
            .mul(shareAcc)
            .div(1e12);
        delegators[msg.sender].availablePeanuts = 0;

        emit WithdrawPeanuts(
            msg.sender,
            delegators[msg.sender].availablePeanuts
        );
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
            uint256 totalPendingPnuts = _getTotalPendingPnut();
            uint256 unmintedPeanuts = totalPendingPnuts.mul(9e11);
            _shareAcc = _shareAcc.add(
                unmintedPeanuts.div(1e12).mul(1e12).div(totalDepositedTSTEEM)
            );
            uint256 pending =
                delegators[msg.sender]
                    .tsteemAmount
                    .mul(_shareAcc)
                    .div(1e12)
                    .sub(delegators[msg.sender].debtRewards);
            return delegators[msg.sender].availablePeanuts.add(pending);
        } else {
            return delegators[msg.sender].availablePeanuts;
        }
    }

    function getDelegatorListLength() public view returns (uint256) {
        return delegatorsList.length;
    }

    function _resetStatus() internal {
        shareAcc = 0;
    }

    function _updateRewardInfo() internal {
        // game has not started
        if (lastRewardBlock == 0) return;

        if (totalDepositedTSTEEM == 0) _resetStatus();

        uint256 currentBlock = block.number;

        // make sure one block can only be calculated one time.
        // think about this situation that more than one deposit/withdraw/withdrowPeanuts transactions
        // were exist in the same block, delegator.amout should be updated after _updateRewardInfo being
        // invoked and it's award peanuts should be calculated next time
        if (currentBlock <= lastRewardBlock) return;
        uint256 totalPendingPnuts = _getTotalPendingPnut();
        uint256 peanutsMintedToDelegators = totalPendingPnuts.mul(9e11);
        uint256 peanutsMintedToDev = totalPendingPnuts.mul(1e11);

        // rewards belong to delegators temporary saved in contract, need delegator withdraw it
        PnutPool.withdrawPeanuts();

        // reward extra peanuts to dev
        Pnuts.transfer(devAddress, peanutsMintedToDev.div(1e12));

        // whenever game being stopped, reset shareAcc
        if (totalDepositedTSTEEM == 0) {
            _resetStatus();
        } else {
            shareAcc = shareAcc.add(
                peanutsMintedToDelegators.div(1e12).mul(1e12).div(
                    totalDepositedTSTEEM
                )
            );
        }

        lastRewardBlock = block.number;
    }

    function _getTotalPendingPnut() internal view returns (uint256) {
        return PnutPool.getPendingPeanuts();
    }
}
