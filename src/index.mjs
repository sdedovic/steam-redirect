export const handler = async (event) => {
  // TODO: remove these and move to appId and args.
  const gameId = event.queryStringParameters.gameId;
  const coreKeeperAppId = 1621690;

  const appId = event?.queryStringParameters?.gameId || coreKeeperAppId;
  const args = event?.queryStringParameters?.args || gameId;

  return {
    statusCode: 302,
    headers: {
      Location: `steam://run/${coreKeeperAppId}//${gameId}/`,
    },
  };
};

