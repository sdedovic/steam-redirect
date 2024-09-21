export const handler = async (event) => {
  const appId = event.queryStringParameters.appId;
  const args = event.queryStringParameters?.args || '';

  return {
    statusCode: 302,
    headers: {
      Location: `steam://run/${appId}//${args}/`,
    },
  };
};

