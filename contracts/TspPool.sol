pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./Ownable.sol";

interface PnutsMining  {
    function transfer(address _to, uint256 _value) external returns (bool success);
}

interface PnutPooling {
    uint256 public shareAcc;
}

interface TspMining {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract TspPooling is Ownable {
    using SafeMath for uint256;

    struct Depositor {
        uint256 amount;             // deposted tsp
        uint256 availablePeanuts;   // minted peanuts for user
        uint256 debtRewards;        // rewards debt 
        bool hasDeposited;          // set true when first time deposit
    }

    mapping(address => Depositor) public depositors;
    address[] public depositorsList;

    PnutsMining Pnuts;
    TspMining Tsp;
    PnutPooling PnutPool;
    
    event Deposit(address depositor, uint256 amount);
    event Withdraw(address depositor, uint256 amount);
    event WithdrawPeanuts(address depositor, uint256 amount);

    modifier onlyDepositor() {
        require(depositors[msg.sender].hasDeposited, "Account is not a depositor");
        _;
    }

    constructor (address _punts, address _pnutPool, address _tsp) public {
        Pnuts = PnutsMining(_punts);
        PnutPool = PnutPooling(_pnutPool);
        Tsp = TspMining(_tsp);
    }

    // Only minter can call this method
    function deposit(uint256 _amount)
        public
    {
        if (_amount == 0) return;
        uint256 tspBalance = Tsp.balanceOf(msg.sender)
        require(_amount <= tspBalance, "ERC20: transfer amount exceeds balance");

        // tansfer tsp from sender to minter
        Tsp.transferFrom(msg.sender, this, _amount);

        uint256 shareAcc = pnutPool.shareAcc;

        // Add to delegator list if account hasn't deposited before
        if(!depositors[msg.sender].hasDeposited) {
            depositors[msg.sender].hasDeposited = true;
            depositors[msg.sender].availablePeanuts = 0;
            depositors[msg.sender].amount = _amount;
            depositors[msg.sender].debtRewards = shareAcc.mul(_amount).div(1e12);
            depositorsList.push(depositors);
            return;
        }

        if (depositors[msg.sender].amount > 0) {
            uint256 pending = depositors[msg.sender].amount.mul(shareAcc).div(1e12).sub(depositors[msg.sender].debtRewards);
            if(pending > 0) {
                depositors[msg.sender].availablePeanuts = depositors[msg.sender].availablePeanuts.add(pending);
            }
        }

        depositors[msg.sender].amount = depositors[msg.sender].amount.add(_amount);

        depositors[msg.sender].debtRewards = depositors[msg.sender].amount.mul(shareAcc).div(1e12);

        emit Deposit(msg.sender, _amount);
    }

    // Only minter can call this method
    function withdraw(uint256 _amount) 
        public
        onlyDepositor
    {
        if (_amount == 0) return;

        if (delegators[delegator].amount == 0) return;
        uint256 shareAcc = pnutPool.shareAcc;
        uint256 pending = depositors[msg.sender].mul(shareAcc).div(1e12).sub(depositors[msg.sender].debtRewards);
        if(pending > 0) {
            depositors[msg.sender].availablePeanuts = depositors[msg.sender].availablePeanuts.add(pending);
        }
        
        uint256 withdrawAmount;
        if (_amount >= depositors[msg.sender].amount)
            withdrawAmount = depositors[msg.sender].amount;
        else
            withdrawAmount = _amount;

        depositors[msg.sender].amount = depositors[msg.sender].amount.sub(withdrawAmount);
        // transfer tsp from this to depositor
        TSP.transferFrom(this, msg.sender, withdrawAmount);

        depositors[msg.sender].debtRewards = depositors[msg.sender].amount.mul(shareAcc).div(1e12);

        emit Withdraw(msg.sender, withdrawAmount);
    }
    
    function withdrawPeanuts() 
        public
        onlyDepositor
    {
        uint256 shareAcc = pnutPool.shareAcc;
        uint256 pending = depositors[msg.sender].amount.mul(shareAcc).div(1e12).sub(depositors[msg.sender].debtRewards);
        if(pending > 0) {
            depositors[msg.sender].availablePeanuts = depositors[msg.sender].availablePeanuts.add(pending);
        }

        Pnuts.transfer(msg.sender, depositors[msg.sender].availablePeanuts);

        depositors[msg.sender].debtRewards = depositors[msg.sender].amount.mul(shareAcc).div(1e12);

        emit WithdrawPeanuts(msg.sender, depositors[msg.sender].availablePeanuts);

        depositors[msg.sender].availablePeanuts = 0;
    }
    
    // pending peanuts >= delegator.availablePeanuts
    function getPendingPeanuts() public view returns (uint256) {
        uint256 _shareAcc = pnutPool.shareAcc;
        uint256 pending = depositors[msg.sender].amount.mul(shareAcc).div(1e12).sub(depositors[msg.sender].debtRewards);
        return depositors[msg.sender].availablePeanuts.add(pending);
    }

    function getDepositorListLength() public view returns(uint256){
        return depositorsList.length;
    }
}