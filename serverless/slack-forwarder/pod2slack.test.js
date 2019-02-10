// @author Alejandro Galue <agalue@opennms.org>

'use strict';

process.env.SLACK_URL = "https://hooks.slack.com/services/xxx/yyy/zzzz";

const app = require('./pod2slack');
const mockAxios = require('axios');

test('Test message generation', async() => {
  const context = {
    request: {
      get: id => {
        switch (id) {
          case 'X-Kubernetes-Event-Type': return 'ADDED';
          case 'X-Kubernetes-Object-Type': return 'Pod';
        }
      },
      body: {
        metadata: {
          name: 'nginx',
          namespace: 'default',
          resourceVersion: 1
        }
      }
    }
  };

  const fissionResults = await app(context);
  expect(fissionResults.status).toBe(200);
  expect(mockAxios.post).toHaveBeenCalledTimes(1);
  expect(mockAxios.post).toHaveBeenCalledWith(process.env.SLACK_URL, {
    text: 'Added Pod nginx@default (version 1)'
  });
});
