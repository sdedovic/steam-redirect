export const handler = async (event) => {
  const appId = event?.queryStringParameters?.gameId || coreKeeperAppId;
  const args = event?.queryStringParameters?.args || gameId;

  return {
    statusCode: 302,
    headers: {
      Location: `steam://run/${appId}//${args}/`,
    },
  };
};

