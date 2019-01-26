// @author Alejandro Galue <agalue@opennms.org>

const axios = require('axios');
const mrkdwn = require('html-to-mrkdwn');
const fs = require('fs');

const configPath = '/configs/default/serverless-config/SLACK_URL';

var slackUrl;
if (fs.existsSync(configPath)) {
  slackUrl = fs.readFileSync(configPath,'utf8');
  console.log('Slack URL: ' + slackUrl);
}

function buildMessage(alarm) {
  const logMsg = mrkdwn(alarm.logMessage).text;
  const descr = mrkdwn(alarm.description).text;
  return `*Alarm ID:${alarm.id}, ${logMsg}*\n${descr}`;
}

module.exports = async function(context) {
  if (slackUrl === undefined) {
    return { status: 404, body: 'The slackUrl is not defined on the config-map.' };
  }
  try {
    const alarm = context.request.body;
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
