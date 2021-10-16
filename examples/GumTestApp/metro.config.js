/**
 * Metro configuration for React Native
 * https://github.com/facebook/react-native
 *
 * @format
 */

module.exports = {
  transformer: {
    getTransformOptions: async () => ({
      transform: {
        // this defeats the RCTDeviceEventEmitter is not a registered callable module
        inlineRequires: true,
      },
    }),
  },
};
