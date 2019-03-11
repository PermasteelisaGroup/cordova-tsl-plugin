var exec = require('cordova/exec');

exports.echo = function (arg0, success, error) {
    exec(success, error, 'RFIDPlugin', 'echo', [arg0]);
};

exports.getDevices = function(success, error) {
    exec(success, error, 'RFIDPlugin', 'getDevices');
};

exports.getConnectedDeviceData = function(success, error) {
    exec(success, error, 'RFIDPlugin', 'getConnectedDeviceData');
};

exports.disconnectDevice = function(success, error) {
    exec(success, error, 'RFIDPlugin', 'disconnectDevice');
};

exports.initPlugin = function(inventoryAlertStatus, readAlertStatus, writeAlertStatus, success, error) {
    exec(success, error, 'RFIDPlugin', 'initPlugin', [inventoryAlertStatus, readAlertStatus, writeAlertStatus]);
};

exports.scan = function(success, error) {
    exec(success, error, 'RFIDPlugin', 'scan');
};

exports.scanAndRead = function(transponderIdentifier, transponderBankMemory, isEPCRead, isPasswordRead, accessPassword, epcMemoryLength, userMemoryLength, success, error) {
    exec(success, error, 'RFIDPlugin', 'scanAndRead', [transponderIdentifier, transponderBankMemory, isEPCRead, isPasswordRead, accessPassword, epcMemoryLength, userMemoryLength]);
};

exports.writeTransponder = function(transponderIdentifier, transponderBankMemory, data, isEPCWrite, isPasswordWrite, accessPassword, epcMemoryLength, userMemoryLength, success, error) {
    exec(success, error, 'RFIDPlugin', 'writeTransponder', [transponderIdentifier, transponderBankMemory, data, isEPCWrite, isPasswordWrite, accessPassword, epcMemoryLength, userMemoryLength]);
};


exports.customScanAndRead = function(transponderIdentifier, transponderBankMemory, offset, length, accessPassword, success, error) {
    exec(success, error, 'RFIDPlugin', 'customScanAndRead', [transponderIdentifier, transponderBankMemory, offset, length, accessPassword]);
};

exports.customWriteTransponder = function(transponderIdentifier, transponderBankMemory, data, offset, accessPassword, success, error) {
    exec(success, error, 'RFIDPlugin', 'customWriteTransponder', [transponderIdentifier, transponderBankMemory, data, offset, accessPassword]);
};


exports.lock = function(transponderIdentifier, lockPayload, accessPassword, success, error) {
    exec(success, error, 'RFIDPlugin', 'lock', [transponderIdentifier, lockPayload, accessPassword]);
};


exports.alert = function(duration, enableBuzzer, enableVibration, tone, success, error) {
    exec(success, error, 'RFIDPlugin', 'alert', [duration, enableBuzzer, enableVibration, tone]);
};

exports.changeInventorySession = function(querySession, success, error) {
    exec(success, error, 'RFIDPlugin', 'changeInventorySession', [querySession]);
};

exports.changeVibrationForCommand = function(commandSelected, status, success, error) {
    exec(success, error, 'RFIDPlugin', 'changeVibrationForCommand', [commandSelected, status]);
};