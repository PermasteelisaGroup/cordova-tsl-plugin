#import "RFIDPlugin.h"
#import <Cordova/CDV.h>
#import <ExternalAccessory/ExternalAccessory.h>
#import <ExternalAccessory/EAAccessoryManager.h>

#import <TSLAsciiCommands/TSLAsciiCommands.h>
#import <TSLAsciiCommands/TSLBinaryEncoding.h>


@interface RFIDPlugin () {
    TSLAsciiCommander *_commander;
}
    @end


@implementation RFIDPlugin
    
- (void)echo:(CDVInvokedUrlCommand*)command
    {
        CDVPluginResult* pluginResult = nil;
        NSString* msg = [command.arguments objectAtIndex:0];
        
        if (msg == nil || [msg length] == 0) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
        } else {
            UIAlertView *toast = [
                                  [UIAlertView alloc] initWithTitle:@""
                                  message:msg
                                  delegate:nil
                                  cancelButtonTitle:nil
                                  otherButtonTitles:nil, nil];
            
            [toast show];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                               [toast dismissWithClickedButtonIndex:0 animated:YES];
                           });
            
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsString:msg];
        }
        
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }
    
    
- (void)initPlugin:(CDVInvokedUrlCommand*)command
    {
        _commander = [[TSLAsciiCommander alloc] init];
        // Some synchronous commands will be used in the app
        [_commander addSynchronousResponder];
        [_commander connect:nil];
        
        // Listen for accessory connect/disconnects
        [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_accessoryDidConnect:) name:EAAccessoryDidConnectNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_accessoryDidDisconnect:) name:EAAccessoryDidDisconnectNotification object:nil];
        
    }
    
    
-(void) _accessoryDidConnect:(NSNotification *)notification {
    EAAccessory *connectedAccessory = [[notification userInfo] objectForKey:EAAccessoryKey];
    [_commander connect:connectedAccessory];
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Device Connected"
                                                    message:@""
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil
                          ];
    [alert show];
    
}
    
- (void)_accessoryDidDisconnect:(NSNotification *)notification
    {
        EAAccessory *connectedAccessory = [[notification userInfo] objectForKey:EAAccessoryKey];
        
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Device Disconnected"
                                                        message:@""
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil
                              ];
        [alert show];
    }
    
    
- (void)getDevices:(CDVInvokedUrlCommand*)command
    {
        [[EAAccessoryManager sharedAccessoryManager] showBluetoothAccessoryPickerWithNameFilter:nil completion:^(NSError *error)
         {
             if( error == nil )
             {
                 // Inform the user that the device is being connected
                 //             _hud = [TSLProgressHUD updateHUD:_hud inView:self.view forBusyState:YES withMessage:@"Waiting for device..."];
             }
             else
             {
                 NSString *errorMessage = nil;
                 switch (error.code)
                 {
                     case EABluetoothAccessoryPickerAlreadyConnected:
                     {
                         NSLog(@"AlreadyConnected");
                         errorMessage = @"That device is already paired!\n\nTry again and wait a few seconds before choosing. Already paired devices will disappear from the list!";
                     }
                     break;
                     
                     case EABluetoothAccessoryPickerResultFailed:
                     case EABluetoothAccessoryPickerResultNotFound:
                     NSLog(@"NotFound");
                     errorMessage = @"Unable to find that device!\n\nEnsure the device is powered on and that the blue LED is flashing.";
                     break;
                     
                     case EABluetoothAccessoryPickerResultCancelled:
                     NSLog(@"Cancelled");
                     break;
                     
                     default:
                     break;
                 }
                 if( errorMessage )
                 {
                     UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Pairing failed..."
                                                                     message:errorMessage
                                                                    delegate:nil
                                                           cancelButtonTitle:@"OK"
                                                           otherButtonTitles:nil
                                           ];
                     [alert show];
                 }
             }
         }];
    }
    
- (void)disconnectDevice:(CDVInvokedUrlCommand*)command
    {
        if (_commander.isConnected) {
            [_commander permanentlyDisconnect];
        }
    }
    
- (void)getConnectedDeviceData:(CDVInvokedUrlCommand*)command
    {
        TSLVersionInformationCommand * versionCommand = [TSLVersionInformationCommand synchronousCommand];
        [_commander executeCommand:versionCommand];
        TSLBatteryStatusCommand *batteryCommand = [TSLBatteryStatusCommand synchronousCommand];
        [_commander executeCommand:batteryCommand];
        
        NSString *msg = [msg stringByAppendingFormat:@"\n%-16s %@\n%-16s %@\n%-16s %@\n%-16s %@\n%-16s %@\n\n",
                         "Manufacturer:", versionCommand.manufacturer,
                         "Serial Number:", versionCommand.serialNumber,
                         "Firmware:", versionCommand.firmwareVersion,
                         "ASCII Protocol:", versionCommand.asciiProtocol,
                         "Battery Level:", [NSString stringWithFormat:@"%d%%", batteryCommand.batteryLevel]];
        
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:msg                                 message:@""
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil
                              ];
        [alert show];
        
    }
    
    @end
