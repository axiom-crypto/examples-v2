// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { AxiomV2Client } from './AxiomV2Client.sol';
import { IERC20 } from '@openzeppelin-contracts/token/ERC20/IERC20.sol';
import { Ownable } from '@openzeppelin-contracts/access/Ownable.sol';
import { IAxiomV2Query } from './interfaces/IAxiomV2Query.sol';

contract AutonomousAirdrop is AxiomV2Client, Ownable {
    struct AxiomV2QueryData {
        uint64 sourceChainId;
        bytes32 dataQueryHash;
        IAxiomV2Query.AxiomV2ComputeQuery computeQuery;
        IAxiomV2Query.AxiomV2Callback callback;
        uint64 maxFeePerGas;
        uint32 callbackGasLimit;
        bytes dataQuery;
    }

    event ClaimAirdrop(
        address indexed user,
        bytes32 indexed queryHash,
        bytes32[] axiomResults,
        bytes callbackExtraData
    );
    event AxiomCallbackQuerySchemaUpdated(bytes32 axiomCallbackQuerySchema);
    event AxiomCallbackCallerAddrUpdated(address axiomCallbackCallerAddr);
    event AirdropTokenAddressUpdated(address token);

    uint64 public callbackSourceChainId;
    address public axiomCallbackCallerAddr;
    bytes32 public axiomCallbackQuerySchema;
    mapping(address => bool) public querySubmitted;
    mapping(address => bool) public hasClaimed;

    IERC20 public token;

    constructor(
        address _axiomV2QueryAddress,
        uint64 _callbackSourceChainId,
        bytes32 _axiomCallbackQuerySchema
    ) AxiomV2Client(_axiomV2QueryAddress) {
        callbackSourceChainId = _callbackSourceChainId;
        axiomCallbackCallerAddr = address(this);
        axiomCallbackQuerySchema = _axiomCallbackQuerySchema;
    }

    function updateCallbackQuerySchema(
        bytes32 _axiomCallbackQuerySchema
    ) public onlyOwner {
        axiomCallbackQuerySchema = _axiomCallbackQuerySchema;
        emit AxiomCallbackQuerySchemaUpdated(_axiomCallbackQuerySchema);
    }

    function updateCallbackCallerAddr(address _axiomCallbackCallerAddr) public onlyOwner {
        axiomCallbackCallerAddr = _axiomCallbackCallerAddr;
        emit AxiomCallbackCallerAddrUpdated(_axiomCallbackCallerAddr);
    }

    function updateAirdropToken(address _token) public onlyOwner {
        token = IERC20(_token);
        emit AirdropTokenAddressUpdated(_token);
    }

    function claimAirdrop(
        AxiomV2QueryData calldata axiomData
    ) external payable {
        // require(!hasClaimed[msg.sender], "User has already claimed this airdrop");
        // require(!querySubmitted[msg.sender], "Query has already been submitted");
        // querySubmitted[msg.sender] = true;
        _validateDataQuery(axiomData.dataQuery);
        bytes32 queryHash = IAxiomV2Query(axiomV2QueryAddress).sendQuery{ value: msg.value }(
            axiomData.sourceChainId,
            axiomData.dataQueryHash,
            axiomData.computeQuery,
            axiomData.callback,
            axiomData.maxFeePerGas,
            axiomData.callbackGasLimit,
            axiomData.dataQuery
        );
    }

    function _validateDataQuery(bytes calldata dataQuery) internal pure {
        bytes32 txHash0 = bytes32(dataQuery[12:44]);
        bytes32 txHash1 = bytes32(dataQuery[86:118]);
        bytes32 txHash2 = bytes32(dataQuery[160:192]);
        require(keccak256(abi.encode(txHash0)) == keccak256(abi.encode(txHash1)), "txHashes for dataQuery do not match");
        require(keccak256(abi.encode(txHash1)) == keccak256(abi.encode(txHash2)), "txHashes for dataQuery do not match");
    }

    function _validateAxiomV2Call(
        uint64 sourceChainId,
        address callerAddr,
        bytes32 querySchema
    ) internal virtual override {
        require(sourceChainId == callbackSourceChainId, "AxiomV2: caller sourceChainId mismatch");
        require(callerAddr == axiomCallbackCallerAddr, "AxiomV2: caller address mismatch");
        require(querySchema == axiomCallbackQuerySchema, "AxiomV2: query schema mismatch");
    }

    function _axiomV2Callback(
        uint64 sourceChainId,
        address callerAddr,
        bytes32 querySchema,
        bytes32 queryHash,
        bytes32[] calldata axiomResults,
        bytes calldata callbackExtraData
    ) internal virtual override {
        address user = abi.decode(callbackExtraData, (address));

        bytes32 eventSchema = axiomResults[0];
        address userAddress = address(uint160(uint256(axiomResults[1])));
        uint32 blockNumber = uint32(uint256(axiomResults[2]));

        require(eventSchema == bytes32(0x4627dbe6b61260f743b8c711823e81d7fcceda009cb16658e1cf79386a3e3228), "Invalid event schema");
        require(userAddress == user, "Invalid user address");
        require(blockNumber > 9000000, "Block number for transaction receipt must be greater than 9000000");

        // Transfer tokens to user
        hasClaimed[user] = true;
        token.transfer(user, 10 ** 18);

        emit ClaimAirdrop(
            user,
            queryHash,
            axiomResults,
            callbackExtraData
        );
        // // AxiomResults come in triplets of []
        // for (uint256 i = 0; i < axiomResults.length; i++) {

        // }
    }
}