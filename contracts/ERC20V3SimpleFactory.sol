/**
 *Submitted for verification at Etherscan.io on 2022-02-21
*/

// File: contracts/lib/CloneFactory.sol

/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity >=0.8.2 <0.9.0;
pragma experimental ABIEncoderV2;

interface ICloneFactory {
    function clone(address prototype) external returns (address proxy);
}

// introduction of proxy mode design: https://docs.openzeppelin.com/upgrades/2.8/
// minimum implementation of transparent proxy: https://eips.ethereum.org/EIPS/eip-1167

contract CloneFactory is ICloneFactory {
    function clone(address prototype) external override returns (address proxy) {
        bytes20 targetBytes = bytes20(prototype);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            proxy := create(0, clone, 0x37)
        }
        return proxy;
    }
}

// File: contracts/lib/InitializableOwnable.sol


/**
 * @title Ownable
 * @author DODO Breeder
 *
 * @notice Ownership related functions
 */
contract InitializableOwnable {
    address public _OWNER_;
    address public _NEW_OWNER_;
    bool internal _INITIALIZED_;

    // ============ Events ============

    event OwnershipTransferPrepared(address indexed previousOwner, address indexed newOwner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ============ Modifiers ============

    modifier notInitialized() {
        require(!_INITIALIZED_, "DODO_INITIALIZED");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == _OWNER_, "NOT_OWNER");
        _;
    }

    // ============ Functions ============

    function initOwner(address newOwner) public notInitialized {
        _INITIALIZED_ = true;
        _OWNER_ = newOwner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        emit OwnershipTransferPrepared(_OWNER_, newOwner);
        _NEW_OWNER_ = newOwner;
    }

    function claimOwnership() public {
        require(msg.sender == _NEW_OWNER_, "INVALID_CLAIM");
        emit OwnershipTransferred(_OWNER_, _NEW_OWNER_);
        _OWNER_ = _NEW_OWNER_;
        _NEW_OWNER_ = address(0);
    }
}

// File: contracts/Factory/ERC20V3Factory.sol

// interface IStdERC20 {
//     function init(
//         address _creator,
//         uint256 _totalSupply,
//         string memory _name,
//         string memory _symbol,
//         uint8 _decimals
//     ) external;
// }

interface IStdERC20 {
    function init(
        address _creator,
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply
    ) external; // external 与public 类似，只不过这些函数只能在合约之外调用 - 它们不能被合约内的其他函数调用
}

/**
 * @title DODO ERC20V2Factory
 * @author DODO Breeder
 *
 * @notice Help user to create erc20 token
 */
contract ERC20V3SimpleFactory is InitializableOwnable {
    // ============ Templates ============

    address public immutable _CLONE_FACTORY_;
    address public _ERC20_TEMPLATE_;
    uint256 public _CREATE_FEE_;

    // ============ Events ============
    // 0 Std
    event NewERC20(address erc20, address creator, uint256 erc20Type);
    event ChangeCreateFee(uint256 newFee);
    event Withdraw(address account, uint256 amount);
    event ChangeStdTemplate(address newStdTemplate);

    // ============ Registry ============
    // creator -> token address list
    mapping(address => address[]) public _USER_STD_REGISTRY_;

    // ============ Functions ============

    fallback() external payable {}

    receive() external payable {}

    // ERC20V3SimpleFactory contract address: https://goerli.etherscan.io/address/0x245380b0f26d69879260b7e60f5e4041473c6666
    constructor(
        // cloneFactory contract address(contract CloneFactory) https://goerli.etherscan.io/address/0x15c50441417b441cbb3a43d858e5f1c0a164d5ad
        address cloneFactory, 
        // erc20Template contract address(can be ERC20TokenABC.sol) https://goerli.etherscan.io/address/0x9a797c9eff86a3ba50712b0a1ae5c42b5a66b550
        address erc20Template, 
        uint256 createFee
    // ) public { // // 0.6.9->0.8.7，需要修订下逻辑，修订方法如下（去掉public）
    ) {
        _CLONE_FACTORY_ = cloneFactory;
        _ERC20_TEMPLATE_ = erc20Template;
        _CREATE_FEE_ = createFee;
    }

    /**
     * @dev Create an ERC20 token.
     */
    function createStdERC20(
        string memory name,
        string memory symbol,
        uint256 totalSupply
        // uint8 decimals
    ) external payable returns (address newERC20) {
        require(msg.value >= _CREATE_FEE_, "CREATE_FEE_NOT_ENOUGH");
        newERC20 = ICloneFactory(_CLONE_FACTORY_).clone(_ERC20_TEMPLATE_); // _CLONE_FACTORY_对应的合约要有clone方法!!!(本文件的contract CloneFactory)
        // IStdERC20(newERC20).init(msg.sender, totalSupply, name, symbol, decimals);
        IStdERC20(newERC20).init(msg.sender, name, symbol, totalSupply); // _ERC20_TEMPLATE_对应的合约要实现IStdERC20接口(且实现其中的init方法)
        _USER_STD_REGISTRY_[msg.sender].push(newERC20);
        emit NewERC20(newERC20, msg.sender, 0);
    }

    // ============ View ============
    function getTokenByUser(address user) 
        external
        view
        returns (address[] memory stds)
    {
        return (_USER_STD_REGISTRY_[user]);
    }

    // ============ Ownable =============
    function changeCreateFee(uint256 newFee) external onlyOwner {
        _CREATE_FEE_ = newFee;
        emit ChangeCreateFee(newFee);
    }

    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        // msg.sender.transfer(amount); // 0.6.9->0.8.7，需要修订下逻辑，修订方法如下（给msg.sender加payable修饰）
        payable(msg.sender).transfer(amount); 
        emit Withdraw(msg.sender, amount);
    }

    function updateStdTemplate(address newStdTemplate) external onlyOwner {
        _ERC20_TEMPLATE_ = newStdTemplate;
        emit ChangeStdTemplate(newStdTemplate);
    }
}