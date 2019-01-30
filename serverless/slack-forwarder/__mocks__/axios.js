// @author Alejandro Galue <agalue@opennms.org>

'use strict';

module.exports = {
  post: jest.fn(() => Promise.resolve({
    status: 200,
    statusText: 'OK',
    data: null
  }))
}