// @author Alejandro Galue <agalue@opennms.org>

'use strict';

process.env.SLACK_URL = "https://hooks.slack.com/services/xxx/yyy/zzzz";
process.env.ONMS_URL = "https://demo.opennms.org/opennms";

const app = require('./alarm2slack');
const mrkdwn = require('html-to-mrkdwn');
const mockAxios = require('axios');

test('Test message generation', async() => {
  const alarm = {
    id: 666,
    uei: 'uei.test/jigsaw',
    logMessage: 'Hello <strong>alejandro</strong>',
    description: '<p>I want to play a game.</p>',
    severity: 6,
    lastEventTime: 1551640812345
  };

  const message = {
    attachments: [{
      title: `Alarm ID: ${alarm.id}`,
      title_link: `${process.env.ONMS_URL}/alarm/detail.htm?id=${alarm.id}`,
      color: '#ff3300',
      pretext: mrkdwn(alarm.logMessage).text,
      text: mrkdwn(alarm.description).text,
      ts: 1551640812,
      fields: [{
        title: "Severity",
        value: "Major",
        short: true
      }]
    }]
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
  expect(mockAxios.post).toHaveBeenCalledWith(process.env.SLACK_URL, message);
});

test('Test missing fields', async() => {
  const test1 = await app.kubeless({data: {}});
  const test2 = await app.kubeless({data: {id: 666}});
  const test3 = await app.kubeless({data: {logMessage: 'blah'}});

  expect(test1.status).toBe(400);
  expect(test2.status).toBe(400);
  expect(test3.status).toBe(400);
});
