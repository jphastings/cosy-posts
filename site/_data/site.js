const DEFAULT_NAME = "Cosy Posts";

module.exports = function () {
  return {
    name: process.env.SITE_NAME || DEFAULT_NAME,
  };
};
