pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./Ownable.sol";

interface ERC20Token {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory); 
    function decimals() external view returns (uint8);
}

contract BlackHole is Ownable{
    using SafeMath for uint256;
    struct BurningInfo {
        ERC20Token token;
        string name;
        string symbol;
        uint8 decimals;
        uint256 amount;
        bool hasAdded;
    }
    mapping(address => ERC20Token) public tokens;
    mapping(address => BurningInfo) public burningInfo;
    address[] public tokensList;

    event AddToken(address token, string name, string symbol, uint8 decimals);
    event BurnToken(address token, uint256 amount);

    constructor(address pnut) public {
        addToken(pnut);
    }

    function addToken(address token) public onlyOwner {
        require(!burningInfo[token].hasAdded, "Token has been added");
        ERC20Token _token = ERC20Token(token);
        tokens[token] = _token;
        tokensList.push(token);
        burningInfo[token].token = _token;
        burningInfo[token].name = _token.name();
        burningInfo[token].symbol = _token.symbol();
        burningInfo[token].decimals = _token.decimals();
        burningInfo[token].amount = 0;
        burningInfo[token].hasAdded = true;
        emit AddToken(token, _token.name(), _token.symbol(), _token.decimals());
    }

    function burnToken(address token, uint256 amount) public {
        require(burningInfo[token].hasAdded, "Token has not been added");
        tokens[token].transferFrom(msg.sender, address(this), amount);
        burningInfo[token].amount = burningInfo[token].amount.add(amount);
        emit BurnToken(token, amount);
    }

    function getTokenListLength() public view returns(uint256) {
        return tokensList.length;
    }
}