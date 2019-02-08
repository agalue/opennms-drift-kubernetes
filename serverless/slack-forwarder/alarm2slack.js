// @author Alejandro Galue <agalue@opennms.org>
// This is intended to work with either Fission or Kubeless
// The SLACK_URL should be provided as a secret or environment variable.

'use strict';

const axios = require('axios');
const mrkdwn = require('html-to-mrkdwn');
const fs = require('fs');

function getSlackUrl() {
  let paths = [
    '/configs/default/serverless-config/SLACK_URL',
    '/secrets/default/serverless-config/SLACK_URL',
    '/serverless-config/SLACK_URL'
  ];
  for (var i=0; i < paths.length; i++) {
    var configPath = paths[i];
    console.log(`Validating path ${configPath}`);
    if (fs.existsSync(configPath)) {
      let slackUrl = fs.readFileSync(configPath,'utf8');
      console.log(`Slack URL ${slackUrl} from ${configPath}`);
      return slackUrl;
    }
  }
  return process.env.SLACK_URL;
}

function buildMessage(alarm) {
  const logMsg = mrkdwn(alarm.logMessage).text;
  const descr = mrkdwn(alarm.description).text;
  return `*Alarm ID:${alarm.id}, ${logMsg}*\n${descr}`;
}

async function sendAlarm(alarm, slackUrl) {
  if (!slackUrl) {
    return { status: 400, body: 'Missing Slack Webhook URL.' };
  }
  if (!alarm.id) {
    return { status: 400, body: 'Missing Alarm ID.' };
  }
  if (!alarm.logMessage) {
    return { status: 400, body: 'Missing Alarm Log Message.' };
  }
  if (!alarm.description) {
    return { status: 400, body: 'Missing Alarm Description.' };
  }
  try {
    console.log('Posting alarm with ID ' + alarm.id + ' to ' + slackUrl);
    const response = await axios.post(slackUrl, {
      text: buildMessage(alarm)
    });
    console.log(response.statusText);
    return { status: 200, body: response.statusText };
  } catch (error) {
    console.error(error);
    return { status: 500, body: 'ERROR: something went wrong. ' + error };
  }
}

var globalSlackUrl = getSlackUrl();

module.exports = {

  fission: async function(context) {
    return await sendAlarm(context.request.body, globalSlackUrl);
  },

  kubeless: async function(event, context) {
    return await sendAlarm(event.data, globalSlackUrl);
  }

}
