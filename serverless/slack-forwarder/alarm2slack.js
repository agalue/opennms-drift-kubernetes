// @author Alejandro Galue <agalue@opennms.org>
// This is intended to work with either Fission or Kubeless
// SLACK_URL and ONMS_URL should be provided as a secret or environment variable.

'use strict';

const axios = require('axios');
const mrkdwn = require('html-to-mrkdwn');
const fs = require('fs');

const severityColors = [
	'#000',
	'#999000',
	'#999',
	'#336600',
	'#ffcc00',
	'#ff9900',
	'#ff3300',
	'#cc0000'
];

const severityNames = [
	'Unknown',
	'Indeterminate',
	'Cleared',
	'Normal',
	'Warning',
	'Minor',
	'Major',
	'Critical'
];

const mandatoryFields = [
  'id',
  'logMessage',
  'description',
  'severity',
  'lastEventTime'
];

function getConfig(attributeName) {
  let paths = [
    '/configs/default/serverless-config',
    '/secrets/default/serverless-config',
    '/serverless-config'
  ];
  for (var i=0; i < paths.length; i++) {
    var configPath = `${paths[i]}/${attributeName}`;
    console.log(`Validating path ${configPath}`);
    if (fs.existsSync(configPath)) {
      let value = fs.readFileSync(configPath,'utf8');
      console.log(`${attributeName} is ${value} from ${configPath}`);
      return value;
    }
  }
  return process.env[attributeName];
}

function buildMessage(alarm) {
  let message = {
    attachments: [{
      title: `Alarm ID: ${alarm.id}`,
      title_link: `${globalOnmsUrl}/alarm/detail.htm?id=${alarm.id}`,
      color: severityColors[alarm.severity],
      pretext: mrkdwn(alarm.logMessage).text,
      text: mrkdwn(alarm.description).text,
      ts: alarm.lastEventTime/1000 | 0,
      fields: [{
        title: 'Severity',
        value: severityNames[alarm.severity],
        short: true
      }]
    }]
  };
  if (alarm.node_criteria) {
    const c = alarm.node_criteria
    const nodeLabel = c.foreign_id ? `${c.foreign_source}:${c.foreign_id}(${c.id})` : `ID=${c.id}`;
    message.fields.push({
      title: 'Node',
      value: nodeLabel,
      short: false
    });
  }
  if (alarm.parameters) {
    alarm.parameters.forEach(p => message.fields.push({
      title: p.name,
      value: p.value,
      short: false
    }));
  }
  console.log(message);
  return message;
}

async function sendAlarm(alarm) {
  console.log('Reveived: ', JSON.stringify(alarm, null, 2));
  if (!globalSlackUrl) {
    return { status: 400, body: 'Missing Slack Webhook URL.' };
  }
  if (!globalOnmsUrl) {
    return { status: 400, body: 'Missing OpenNMS URL.' };
  }
  for (let i=0; i<mandatoryFields.length; i++) {
    const field = mandatoryFields[i];
    if (!alarm[field]) {
      return { status: 400, body: `Missing Alarm Field ${field}.` };
    }
  }
  try {
    const response = await axios.post(globalSlackUrl, buildMessage(alarm));
    console.log(response.statusText);
    return { status: 200, body: response.statusText };
  } catch (error) {
    console.error(error);
    return { status: 500, body: `ERROR: something went wrong. ${error}` };
  }
}

var globalSlackUrl = getConfig('SLACK_URL');
var globalOnmsUrl = getConfig('ONMS_URL');

module.exports.fission = async function(context) {
  return await sendAlarm(context.request.body);
};

module.exports.kubeless = async function(event, context) {
  return await sendAlarm(event.data);
};
