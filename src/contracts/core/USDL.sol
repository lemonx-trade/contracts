// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./YieldToken.sol";
import "./interfaces/IUSDL.sol";

contract USDL is YieldToken, IUSDL {
    mapping(address => bool) public vaults;

    modifier onlyVault() {
        require(vaults[msg.sender], "USDL: forbidden");
        _;
    }

    modifier isContract(address account) {
        require(account != address(0), "nulladd");
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        require(size > 0, "eoa");
        _;
    }

    constructor(address _vault) YieldToken("USD LemonX", "USDL", 0) {
        vaults[_vault] = true;
    }
    //  M2 check for isContract

    function addVault(address _vault) external override onlyGov isContract(_vault) {
        vaults[_vault] = true;
    }
    //  M2 check for isContract

    function removeVault(address _vault) external override onlyGov isContract(_vault) {
        vaults[_vault] = false;
    }

    function mint(address _account, uint256 _amount) external override onlyVault {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override onlyVault {
        _burn(_account, _amount);
    }
}
