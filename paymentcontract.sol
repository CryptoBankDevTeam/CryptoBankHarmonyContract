// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "./uniswapv2/libraries/TransferHelper.sol";

import "./uniswapv2/interfaces/IERC20.sol";

interface IUniswapV2Router02 {

    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForTokens(

        uint256 amountIn,

        uint256 amountOutMin,

        address[] calldata path,

        address to,

        uint256 deadline

    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(

        uint256 amountOut,

        uint256 amountInMax,

        address[] calldata path,

        address to,

        uint256 deadline

    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path)

        external

        view

        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)

        external

        view

        returns (uint256[] memory amounts);

}

contract PaymentContract {

    address public owner;

    address public swapRouter;

    address public WBNB;

    address public stableCoin;

    uint256 public slippage;

    IERC20Uniswap stableCoinContract;

    // Defining the vendors array

    //struct vendor {

    //    string vendorName;

    //    uint vendorBalance;

    //}

    struct vendor {

        string vendorName;

        mapping(string => uint256) vendorBalance;

    }

    //vendor[] public vendors;

    mapping(string => vendor) public vendors;

    modifier onlyOwner() {

        require(msg.sender == owner, "only owner can call this function!");

        _;

    }

    // Events

    event paymentSuccessful(

        string _transactionId,

        uint256 _amountInUSD,

        string _vendorId,

        string _fiatSymbol,

        uint256 _fiatAmount,

        address buyer,

        uint256 _timestamp

    );

    event newVendorRegistered(string name, string _vendorId);

    event updatedRouter(address _previousRouter, address _newRouter);

    event updatedStableCoin(

        address _previousStableCoin,

        address _newStableCoin

    );

    event updatedSlippage(uint256 _previousSlippage, uint256 _newSlippage);

    event swapSuccessful(

        uint256 _tokenAmount,

        uint256 _amountInUSD,

        uint256[] amountOut,

        string _tokenSymbol,

        string _stableCoinSymbol,

        address buyer,

        string _transactionId

    );

    event tradeSuccessful(

        string _vendorId,

        string _transactionId,

        string _tradeId,

        address _traderAddress,

        uint256 _amount,

        string _stableCoinSymbol

    );

    constructor(

        address _swapRouter,

        address _WBNB,

        address _stableCoin,

        uint256 _slippage

    ) public {

        swapRouter = _swapRouter;

        WBNB = _WBNB;

        stableCoin = _stableCoin;

        stableCoinContract = IERC20Uniswap(stableCoin);

        slippage = _slippage;

        owner = msg.sender;

    }

    function setRouter(address _swapRouter, address _WBNB) public onlyOwner {

        address _previousRouter = swapRouter;

        swapRouter = _swapRouter;

        WBNB = _WBNB;

        emit updatedRouter(_previousRouter, _swapRouter);

    }

    function setStableCoin(address _stableCoin) public onlyOwner {

        address _previousStableCoin = stableCoin;

        stableCoin = _stableCoin;

        stableCoinContract = IERC20Uniswap(stableCoin);

        emit updatedStableCoin(_previousStableCoin, _stableCoin);

    }

    function setSlippage(uint256 _slippage) public onlyOwner {

        uint256 _previousSlippage = slippage;

        slippage = _slippage;

        emit updatedSlippage(_previousSlippage, _slippage);

    }

    /*

   function registerANewVendor(string memory _name) public onlyOwner returns(uint){

        uint _Id = vendors.length - 1;

        vendor memory newVendor;

        newVendor.vendorName = _name;

        newVendor.vendorBalance = 0;

        

        vendors.push(newVendor);

        emit newVendorRegistered(_name, _Id);

        return _Id;

    }

**/

    function registerANewVendor(string memory _name, string memory _vendorId)

        public

        onlyOwner

    {

        // uint _Id = vendors.length - 1;

        vendor memory newVendor;

        newVendor.vendorName = _name;

        // newVendor.vendorBalance[stableCoinContract.symbol()] = 0;

        // vendors.push(newVendor);

        vendors[_vendorId] = newVendor;

        emit newVendorRegistered(_name, _vendorId);

    }

    function vendorBalance(

        string memory vendorId,

        string memory stableCoinSymbol

    ) public view returns (uint256) {

        return vendors[vendorId].vendorBalance[stableCoinSymbol];

    }

    // Allows a buyer to make payment

    function makePayment(

        string memory _vendorId,

        address _token,

        uint256 _amountInUSD,

        string memory _fiatSymbol,

        uint256 _fiatAmount,

        string memory _tokenSymbol,

        string memory _transactionId

    ) public {

        require(bytes(_vendorId).length > 0, "vendor does not exist!");

        // Always take WBNB path to get a better rate

        address[] memory _path;

        /*

        if (_token == WBNB) {

             _path = new address[](2);

            _path[0] = _token;

            _path[1] = stableCoin;

        } else{

            _path = new address[](3);

            _path[0] = _token;

            _path[1] = WBNB;

            _path[2] = stableCoin;

        }

        **/

        _path = new address[](2);

        _path[0] = _token;

        _path[1] = stableCoin;

        // msg.sender must approve this contract to spend their tokens

        if (_token != stableCoin) {

            // Get the amount of token to swap

            uint256 _tokenAmount = _requiredTokenAmount(_amountInUSD, _path);

            // Before swap balance

            uint256 beforeSwap = IERC20Uniswap(_token).balanceOf(address(this));

            // Takes the tokens from buyer account

            TransferHelper.safeTransferFrom(

                _token,

                msg.sender,

                address(this),

                _tokenAmount + _tokenAmount * slippage

            );

            // Swap to stableCoin

            uint256[] memory amountOut = _swap(

                _tokenAmount,

                _amountInUSD,

                _path

            );

            // After swap balance

            uint256 afterSwap = IERC20Uniswap(_token).balanceOf(address(this));

            // return excess to buyer

            uint256 excess = afterSwap - beforeSwap;

            TransferHelper.safeTransfer(_token, msg.sender, excess);

            emit swapSuccessful(

                _tokenAmount,

                _amountInUSD,

                amountOut,

                _tokenSymbol,

                stableCoinContract.symbol(),

                msg.sender,

                _transactionId

            );

        } else {

            TransferHelper.safeTransferFrom(

                _token,

                msg.sender,

                address(this),

                _amountInUSD

            );

        }

        // Updates vendor's balance

        vendors[_vendorId].vendorBalance[

            stableCoinContract.symbol()

        ] = _amountInUSD;

        // string memory _transactionId = _generateTransactionId(_vendorId);

        // emit payment recieve event

        emit paymentSuccessful(

            _transactionId,

            _amountInUSD,

            _vendorId,

            _fiatSymbol,

            _fiatAmount,

            msg.sender,

            block.timestamp

        );

    }

    // Internal funtions

    function _requiredTokenAmount(uint256 _amountInUSD, address[] memory _path)

        public

        view

        returns (uint256)

    {

        uint256[] memory _tokenAmount = IUniswapV2Router02(swapRouter)

            .getAmountsIn(_amountInUSD, _path);

        return _tokenAmount[0];

    }

    /*

    function _generateTransactionId(string memory _vendorID) public view returns(string memory){

        uint256 time = block.timestamp;

        uint256 exponent;

        while (time >= 10) {

            time /= 10;

            exponent++;

        }

        // uint _transactionID = _vendorID * 10 ** (exponent + 1) + block.timestamp;

        string memory _transactionID = _vendorID + block.timestamp;

        return _transactionID;

    }

    

    **/

    // Swap from tokens to a stablecoin

    function _swap(

        uint256 _tokenAmount,

        uint256 _amountInUSD,

        address[] memory _path

    ) internal returns (uint256[] memory amountOut) {

        // Approve the router to swap token.

        TransferHelper.safeApprove(_path[0], swapRouter, _tokenAmount);

        amountOut = IUniswapV2Router02(swapRouter).swapTokensForExactTokens(

            _amountInUSD,

            _tokenAmount + (slippage / 100) * _tokenAmount,

            _path,

            address(this),

            block.timestamp

        );

        // emit swapSuccessful(_tokenAmount, _amountInUSD, amountOut);

    }

    // SendTokens() is the function that releases the token to a trader

    // from is expected to be a vendor's ID

    function sendTokens(

        uint256 _amount,

        string memory _from,

        address _traderAddress,

        string memory _transactionId,

        string memory _tradeId,

        string memory _stableCoinSymbol

    ) public onlyOwner {

        require(

            _amount <= vendors[_from].vendorBalance[_stableCoinSymbol],

            "not enough balance!"

        );

        vendors[_from].vendorBalance[_stableCoinSymbol] -= _amount;

        TransferHelper.safeTransfer(stableCoin, _traderAddress, _amount);

        emit tradeSuccessful(

            _from,

            _transactionId,

            _tradeId,

            _traderAddress,

            _amount,

            stableCoinContract.symbol()

        );

    }

}
