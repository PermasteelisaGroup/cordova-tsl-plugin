#import <Cordova/CDV.h>

@interface RFIDPlugin : CDVPlugin

- (void)echo:(CDVInvokedUrlCommand*)command;
- (void)initPlugin:(CDVInvokedUrlCommand*)command;
- (void)getDevices:(CDVInvokedUrlCommand*)command;
- (void)disconnectDevice:(CDVInvokedUrlCommand*)command;
- (void)getConnectedDeviceData:(CDVInvokedUrlCommand*)command;

- (void)scan:(CDVInvokedUrlCommand*)command;
- (void)scanAndRead:(CDVInvokedUrlCommand*)command;

- (void)writeTransponder:(CDVInvokedUrlCommand*)command;

- (void)customScanAndRead:(CDVInvokedUrlCommand*)command;
- (void)customWriteTransponder:(CDVInvokedUrlCommand*)command;

- (void)initConnectedReader:(BOOL) isConnected;

@end
