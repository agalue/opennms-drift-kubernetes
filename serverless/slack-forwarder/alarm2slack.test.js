// @author Alejandro Galue <agalue@opennms.org>

'use strict';

process.env.SLACK_URL = "https://hooks.slack.com/services/xxx/yyy/zzzz";

const app = require('./alarm2slack');
const mockAxios = require('axios');

test('Test message generation', async() => {
  await app.kubeless({
    data: {
      id: 666,
      uei: 'uei.test/jigsaw',
      logMessage: 'Hello <strong>alejandro</strong>',
      description: '<p>I want to play a game.</p>'
    }
  });

  expect(mockAxios.post).toHaveBeenCalledWith(process.env.SLACK_URL, {
      text: '*Alarm ID:666, Hello *alejandro**\nI want to play a game.'
  });
});
