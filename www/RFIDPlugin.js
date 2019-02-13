var exec = require('cordova/exec');


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



exports.echo = function(arg0, success, error) {
    exec(success, error, 'ModusEchoSwift', 'echo', [arg0]);
};

exports.echojs = function(arg0, success, error) {
    if (arg0 && typeof(arg0) === 'string' && arg0.length > 0) {
        success(arg0);
    } else {
        error('Empty message!');
    }
};