// @author Alejandro Galue <agalue@opennms.org>

'use strict';

process.env.SLACK_URL = "https://hooks.slack.com/services/xxx/yyy/zzzz";

const app = require('./alarm2slack');
const mockAxios = require('axios');

test('Test message generation', async() => {
  const alarm = {
    id: 666,
    uei: 'uei.test/jigsaw',
    logMessage: 'Hello <strong>alejandro</strong>',
    description: '<p>I want to play a game.</p>'
  };

  const kubelessResults = await app.kubeless({
    data: alarm
  });

  const fissionResults = await app.fission({
    request: { body: alarm }
  });

  expect(kubelessResults.status).toBe(200);
  expect(fissionResults.status).toBe(200);
  expect(mockAxios.post).toHaveBeenCalledTimes(2);
  expect(mockAxios.post).toHaveBeenCalledWith(process.env.SLACK_URL, {
      text: '*Alarm ID:666, Hello *alejandro**\nI want to play a game.'
  });
});
