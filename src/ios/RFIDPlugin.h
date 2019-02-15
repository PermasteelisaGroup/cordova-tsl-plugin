#import <Cordova/CDV.h>

@interface RFIDPlugin : CDVPlugin
    
- (void)echo:(CDVInvokedUrlCommand*)command;
- (void)initPlugin:(CDVInvokedUrlCommand*)command;
- (void)getDevices:(CDVInvokedUrlCommand*)command;
- (void)disconnectDevice:(CDVInvokedUrlCommand*)command;
- (void)getConnectedDeviceData:(CDVInvokedUrlCommand*)command;
    
@end
