// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../libraries/token/IERC20.sol";
import "./interfaces/IYieldToken.sol";
import "../libraries/token/SafeERC20.sol";

contract YieldToken is IERC20, IYieldToken {
    using SafeERC20 for IERC20;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public override totalSupply;
    uint256 public nonStakingSupply;

    address public gov;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    mapping(address => bool) public nonStakingAccounts;
    mapping(address => bool) public admins;

    bool public inWhitelistMode;
    mapping(address => bool) public whitelistedHandlers;

    modifier onlyGov() {
        require(msg.sender == gov, "YieldToken: forbidden");
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "YieldToken: forbidden");
        _;
    }

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        gov = msg.sender;
        admins[msg.sender] = true;
        _mint(msg.sender, _initialSupply);
    }
    // TODO: L1 missing events
    // TODO: L4 zero or dead address check

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }
    // TODO: L1 missing events

    function setInfo(string memory _name, string memory _symbol) external onlyGov {
        name = _name;
        symbol = _symbol;
    }
    // TODO: L1 missing events
    // TODO: L4 zero or dead address check

    function addAdmin(address _account) external onlyGov {
        admins[_account] = true;
    }
    // TODO: L4 zero or dead address check

    function removeAdmin(address _account) external override onlyGov {
        admins[_account] = false;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }
    // TODO: L1 missing events

    function setInWhitelistMode(bool _inWhitelistMode) external onlyGov {
        inWhitelistMode = _inWhitelistMode;
    }
    // TODO: L1 missing events

    function setWhitelistedHandler(address _handler, bool _isWhitelisted) external onlyGov {
        whitelistedHandlers[_handler] = _isWhitelisted;
    }
    // TODO: L1 missing events

    function addNonStakingAccount(address _account) external onlyAdmin {
        require(!nonStakingAccounts[_account], "YieldToken: _account already marked");
        nonStakingAccounts[_account] = true;
        nonStakingSupply = nonStakingSupply + (balances[_account]);
    }
    // TODO: L1 missing events

    function removeNonStakingAccount(address _account) external onlyAdmin {
        require(nonStakingAccounts[_account], "YieldToken: _account not marked");
        nonStakingAccounts[_account] = false;
        nonStakingSupply = nonStakingSupply - (balances[_account]);
    }

    function totalStaked() external view override returns (uint256) {
        return totalSupply - (nonStakingSupply);
    }

    function balanceOf(address _account) external view override returns (uint256) {
        return balances[_account];
    }

    function stakedBalance(address _account) external view override returns (uint256) {
        if (nonStakingAccounts[_account]) {
            return 0;
        }
        return balances[_account];
    }

    function transfer(address _recipient, uint256 _amount) external override returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) external view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external override returns (bool) {
        if (allowances[_sender][msg.sender] < (_amount)) {
            revert("YieldToken: transfer amount exceeds allowance");
        }
        uint256 nextAllowance = allowances[_sender][msg.sender] - _amount;
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "YieldToken: mint to the zero address");

        totalSupply = totalSupply + (_amount);
        balances[_account] = balances[_account] + (_amount);

        if (nonStakingAccounts[_account]) {
            nonStakingSupply = nonStakingSupply + (_amount);
        }

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "YieldToken: burn from the zero address");
        if (balances[_account] < _amount) {
            revert("YieldToken: burn amount exceeds balance");
        }

        balances[_account] = balances[_account] - _amount;
        totalSupply = totalSupply - (_amount);

        if (nonStakingAccounts[_account]) {
            nonStakingSupply = nonStakingSupply - (_amount);
        }

        emit Transfer(_account, address(0), _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "YieldToken: transfer from the zero address");
        require(_recipient != address(0), "YieldToken: transfer to the zero address");

        if (inWhitelistMode) {
            require(whitelistedHandlers[msg.sender], "YieldToken: msg.sender not whitelisted");
        }
        if (balances[_sender] < _amount) {
            revert("YieldToken: transfer amount exceeds balance");
        }

        balances[_sender] = balances[_sender] - _amount;
        balances[_recipient] = balances[_recipient] + (_amount);

        if (nonStakingAccounts[_sender]) {
            nonStakingSupply = nonStakingSupply - (_amount);
        }
        if (nonStakingAccounts[_recipient]) {
            nonStakingSupply = nonStakingSupply + (_amount);
        }

        emit Transfer(_sender, _recipient, _amount);
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "YieldToken: approve from the zero address");
        require(_spender != address(0), "YieldToken: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }
}
