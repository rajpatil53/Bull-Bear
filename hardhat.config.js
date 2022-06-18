require("@nomiclabs/hardhat-waffle");
require("dotenv").config({ path: ".env" });
/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.7",
  networks: {
    hardhat: {
    },
    rinkeby: {
      url: process.env.ALCHEMY_APP_URL,
      accounts: [process.env.PRIVATE_KEY]
    }
  },
};
