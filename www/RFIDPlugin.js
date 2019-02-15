var exec = require('cordova/exec');

exports.echo = function (arg0, success, error) {
    exec(success, error, 'RFIDPlugin', 'echo', [arg0]);
};

exports.getDevices = function(arg0, success, error) {
    exec(success, error, 'RFIDPlugin', 'getDevices', [arg0]);
};

exports.getConnectedDeviceData = function(arg0, success, error) {
    exec(success, error, 'RFIDPlugin', 'getConnectedDeviceData', [arg0]);
};

exports.disconnectDevice = function(arg0, success, error) {
    exec(success, error, 'RFIDPlugin', 'disconnectDevice', [arg0]);
};

exports.initPlugin = function(arg0, success, error) {
    exec(success, error, 'RFIDPlugin', 'initPlugin', [arg0]);
};
