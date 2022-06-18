// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Chainlink Imports
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
// This import includes functions from both ./KeeperBase.sol and
// ./interfaces/KeeperCompatibleInterface.sol
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

// VRF imports
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract BullBear is ERC721, ERC721Enumerable, ERC721URIStorage, KeeperCompatibleInterface, Ownable, VRFConsumerBaseV2 {
    using Counters for Counters.Counter;
    enum MarketTrend {BULL, BEAR}

    MarketTrend public currentMarketTrend = MarketTrend.BULL; 

    Counters.Counter private _tokenIdCounter;
    AggregatorV3Interface public pricefeed;

    // VRF variables
    VRFCoordinatorV2Interface COORDINATOR;
    // Your subscription ID.
    uint64 s_subscriptionId;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf-contracts/#configurations
    bytes32 keyHash = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
    // so 100,000 is a safe default for this example contract. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 callbackGasLimit = 500000;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 numWords =  1;
    uint256[] public s_randomWords;
    uint256 public s_requestId;
    
    /**
    * Use an interval in seconds and a timestamp to slow execution of Upkeep
    */
    uint public /* immutable */ interval; 
    uint public lastTimeStamp;

    int256 public currentPrice;
    
    // IPFS URIs for the dynamic nft graphics/metadata.
    // NOTE: These connect to my IPFS Companion node.
    // You should upload the contents of the /ipfs folder to your own node for development.
    string[] bullUrisIpfs = [
        "https://ipfs.io/ipfs/QmRXyfi3oNZCubDxiVFre3kLZ8XeGt6pQsnAQRZ7akhSNs?filename=gamer_bull.json",
        "https://ipfs.io/ipfs/QmRJVFeMrtYS2CUVUM2cHJpBV5aX2xurpnsfZxLTTQbiD3?filename=party_bull.json",
        "https://ipfs.io/ipfs/QmdcURmN1kEEtKgnbkVJJ8hrmsSWHpZvLkRgsKKoiWvW9g?filename=simple_bull.json"
    ];
    string[] bearUrisIpfs = [
        "https://ipfs.io/ipfs/Qmdx9Hx7FCDZGExyjLR6vYcnutUR8KhBZBnZfAPHiUommN?filename=beanie_bear.json",
        "https://ipfs.io/ipfs/QmTVLyTSuiKGUEmb88BgXG3qNC8YgpHZiFbjHrXKH3QHEu?filename=coolio_bear.json",
        "https://ipfs.io/ipfs/QmbKhBXVWmwrYsTPFYfroR2N7NAekAMxHUVg2CWks7i9qj?filename=simple_bear.json"
    ];

    event TokensUpdated(string marketTrend);

    // For testing with the mock on Rinkeby, pass in 10(seconds) for `updateInterval` and the address of my 
    // deployed  MockPriceFeed.sol contract (0xD753A1c190091368EaC67bbF3Ee5bAEd265aC420).
    constructor(uint updateInterval, address _pricefeed, address _vrfCoordinator) ERC721("Bull&Bear", "BBTK") VRFConsumerBaseV2(_vrfCoordinator) {
        // Set the keeper update interval
        interval = updateInterval; 
        lastTimeStamp = block.timestamp;  //  seconds since unix epoch

        // set the price feed address to
        // BTC/USD Price Feed Contract Address on Rinkeby: https://rinkeby.etherscan.io/address/0xECe365B379E1dD183B20fc5f022230C044d51404
        // or the MockPriceFeed Contract
        pricefeed = AggregatorV3Interface(_pricefeed); // To pass in the mock

        // set the price for the chosen currency pair.
        currentPrice = getLatestPrice();
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
    }

    function safeMint(address to) public  {
        // Current counter value will be the minted token's token ID.
        uint256 tokenId = _tokenIdCounter.current();

        // Increment it so next time it's correct when we call .current()
        _tokenIdCounter.increment();

        // Mint the token
        _safeMint(to, tokenId);

        // Default to a bull NFT
        string memory defaultUri = bullUrisIpfs[0];
        _setTokenURI(tokenId, defaultUri);
    }

    function checkUpkeep(bytes calldata /* checkData */) external view override returns (bool upkeepNeeded, bytes memory /*performData */) {
         upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
    }

    function performUpkeep(bytes calldata /* performData */ ) external override {
        //We highly recommend revalidating the upkeep in the performUpkeep function
        if ((block.timestamp - lastTimeStamp) > interval ) {
            lastTimeStamp = block.timestamp;         
            int latestPrice =  getLatestPrice(); 
        
            if (latestPrice == currentPrice) {
                return;
            }

            if (latestPrice < currentPrice) {
                // bear
                currentMarketTrend = MarketTrend.BEAR;

            } else {
                // bull
                currentMarketTrend = MarketTrend.BULL;
            }

            // update currentPrice
            currentPrice = latestPrice;

            requestRandomIndexNumber();
        } else {
            return;
        }

       
    }

    // Helpers
    function getLatestPrice() public view returns (int256) {
         (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = pricefeed.latestRoundData();

        return price; //  example price returned 3034715771688
    }

    function requestRandomIndexNumber() internal {
        require(s_subscriptionId != 0, "Subscription ID not set.");

        s_requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

    }

    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        s_randomWords = randomWords;

        string[] memory nftUris = currentMarketTrend == MarketTrend.BULL ? bullUrisIpfs : bearUrisIpfs;

        uint256 randomIndex = randomWords[0] % 3;

        for (uint i = 0; i < _tokenIdCounter.current() ; i++) {
            _setTokenURI(i, nftUris[randomIndex]);
        }  
        
        string memory trend = currentMarketTrend == MarketTrend.BULL ? "bull" : "bear";

        emit TokensUpdated(trend);
    }

    function setPriceFeed(address newFeed) public onlyOwner {
        pricefeed = AggregatorV3Interface(newFeed);
    }
    function setInterval(uint256 newInterval) public onlyOwner {
        interval = newInterval;
    }
    function setVRFCoordinator(address coordinatorAddress) public onlyOwner {
        COORDINATOR = VRFCoordinatorV2Interface(coordinatorAddress);
    }
    function setVRFSubscriptionId(uint64 subscriptionId) public onlyOwner {
        s_subscriptionId = subscriptionId;
    }
    

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }


    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}