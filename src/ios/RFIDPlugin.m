#import "RFIDPlugin.h"
#import <Cordova/CDV.h>
#import <ExternalAccessory/ExternalAccessory.h>
#import <ExternalAccessory/EAAccessoryManager.h>

//#import <TSLAsciiCommands/TSLAsciiCommands.h>
//#import <TSLAsciiCommands/TSLBinaryEncoding.h>

// Helpers
#import <TSLAsciiCommands/TSLBinaryEncoding.h>
#import <TSLAsciiCommands/TSLConstants.h>
#import <TSLAsciiCommands/TSLExceptions.h>
#import <TSLAsciiCommands/TSLTriState.h>
#import <TSLAsciiCommands/TSLDeleteConfirmation.h>
#import <TSLAsciiCommands/TSLDeviceFileLineReceived.h>

// Commander
#import <TSLAsciiCommands/TSLAsciiCommander.h>

// Commands
#import <TSLAsciiCommands/TSLVersionInformationCommand.h>
#import <TSLAsciiCommands/TSLBatteryStatusCommand.h>
#import <TSLAsciiCommands/TSLDateCommand.h>
#import <TSLAsciiCommands/TSLTimeCommand.h>
#import <TSLAsciiCommands/TSLDateTimeCommand.h>
#import <TSLAsciiCommands/TSLSleepCommand.h>
#import <TSLAsciiCommands/TSLSwitchActionCommand.h>
#import <TSLAsciiCommands/TSLSwitchStateCommand.h>
#import <TSLAsciiCommands/TSLInventoryCommand.h>
#import <TSLAsciiCommands/TSLAbortCommand.h>
#import <TSLAsciiCommands/TSLFactoryDefaultsCommand.h>
#import <TSLAsciiCommands/TSLReadTransponderCommand.h>
#import <TSLAsciiCommands/TSLWriteSingleTransponderCommand.h>
#import <TSLAsciiCommands/TSLBarcodeCommand.h>
#import <TSLAsciiCommands/TSLAlertCommand.h>
#import <TSLAsciiCommands/TSLEchoCommand.h>
#import <TSLAsciiCommands/TSLTransponderSelectCommand.h>
#import <TSLAsciiCommands/TSLSwitchSinglePressUserActionCommand.h>
#import <TSLAsciiCommands/TSLSwitchDoublePressUserActionCommand.h>
#import <TSLAsciiCommands/TSLSwitchSinglePressCommand.h>
#import <TSLAsciiCommands/TSLSwitchDoublePressCommand.h>
#import <TSLAsciiCommands/TSLWriteAutorunFileCommand.h>
#import <TSLAsciiCommands/TSLReadAutorunFileCommand.h>
#import <TSLAsciiCommands/TSLExecuteAutorunFileCommand.h>
#import <TSLAsciiCommands/TSLReadLogFileCommand.h>
#import <TSLAsciiCommands/TSLLockCommand.h>
#import <TSLAsciiCommands/TSLWriteTransponderCommand.h>
#import <TSLAsciiCommands/TSLKillCommand.h>
#import <TSLAsciiCommands/TSLLicenceKeyCommand.h>
#import <TSLAsciiCommands/TSLSleepTimeoutCommand.h>

// Responders
#import <TSLAsciiCommands/TSLAsciiCommandResponderBase.h>
#import <TSLAsciiCommands/TSLLoggerResponder.h>
#import <TSLAsciiCommands/TSLSwitchResponder.h>
#import <TSLAsciiCommands/TSLTransponderResponder.h>

#import <TSLAsciiCommands/TSLTransponderData.h>
#import <TSLAsciiCommands/TSLTransponderAccessErrorCode.h>
#import <TSLAsciiCommands/TSLTransponderBackscatterErrorCode.h>

// Protocols
#import <TSLAsciiCommands/TSLAsciiCommandResponseNotifying.h>
#import <TSLAsciiCommands/TSLTransponderReceivedDelegate.h>


@interface RFIDPlugin () <TSLInventoryCommandTransponderReceivedDelegate> {
    TSLAsciiCommander *_commander;
    TSLInventoryCommand *_inventaryCommand;
    
    TSLReadTransponderCommand *_readerCommand;
    TSLWriteTransponderCommand *_writeCommand;
    
    NSString *_connectCallbackId;
    NSString *_disconnectCallbackId;
    NSString *_scanCallbackId;
    
    NSMutableDictionary<NSString *, TSLTransponderData *> *_transpondersRead;
    
}
@end


@implementation RFIDPlugin

- (void)echo:(CDVInvokedUrlCommand*)command {
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


- (void)initPlugin:(CDVInvokedUrlCommand*)command {
    _commander = [[TSLAsciiCommander alloc] init];
    // Some synchronous commands will be used in the app
    [_commander addSynchronousResponder];
    [_commander connect:nil];
    
    
    // Listen for accessory connect/disconnects
    [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_accessoryDidConnect:) name:EAAccessoryDidConnectNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_accessoryDidDisconnect:) name:EAAccessoryDidDisconnectNotification object:nil];
    
    
    // Listen for change in TSLAsciiCommander state
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(commanderChangedState:) name:TSLCommanderStateChangedNotification object:_commander];
    
    
    [self initConnectedReader:_commander.isConnected];
    
    CDVPluginResult* pluginResult = nil;
    if (_commander.isConnected) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                         messageAsString:@"Plugin ready, device is connected"];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"Plugin ready, no connected device"];
    }
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}



-(void)commanderChangedState:(NSNotification *)notification
{
    // The connected state is indicated by the presence or absence of userInfo
    BOOL isConnected = notification.userInfo != nil;
    
    [self initConnectedReader: isConnected];
}


-(void) _accessoryDidConnect:(NSNotification *)notification {
    EAAccessory *connectedAccessory = [[notification userInfo] objectForKey:EAAccessoryKey];
    [_commander connect:connectedAccessory];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsString:@"Device Connected"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:_connectCallbackId];
    
    
}

- (void)_accessoryDidDisconnect:(NSNotification *)notification {
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsString:@"Device Disconnected"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:_disconnectCallbackId];
}


- (void)getDevices:(CDVInvokedUrlCommand*)command {
    
    [[EAAccessoryManager sharedAccessoryManager] showBluetoothAccessoryPickerWithNameFilter:nil completion:^(NSError *error) {
        if( error == nil )
        {
            // Inform the user that the device is being connected
            //             _hud = [TSLProgressHUD updateHUD:_hud inView:self.view forBusyState:YES withMessage:@"Waiting for device..."];
            
            _connectCallbackId = command.callbackId;
            
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

- (void)disconnectDevice:(CDVInvokedUrlCommand*)command {
    if (_commander.isConnected) {
        [_commander permanentlyDisconnect];
        
        _disconnectCallbackId = command.callbackId;
    }
}

- (void)getConnectedDeviceData:(CDVInvokedUrlCommand*)command {
    TSLVersionInformationCommand * versionCommand = [TSLVersionInformationCommand synchronousCommand];
    [_commander executeCommand:versionCommand];
    TSLBatteryStatusCommand *batteryCommand = [TSLBatteryStatusCommand synchronousCommand];
    [_commander executeCommand:batteryCommand];
    
    NSString *msg = [NSString stringWithFormat:@"Manufacturer: %@\nSerial Number: %@\nFirmware: %@\nBattery Level: %@", versionCommand.manufacturer, versionCommand.serialNumber, versionCommand.firmwareVersion, [NSString stringWithFormat:@"%d%%", batteryCommand.batteryLevel]];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsString:msg];
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
    
}


- (void)scan:(CDVInvokedUrlCommand*)command {
    
    _scanCallbackId = command.callbackId;
    
    [_commander executeCommand:_inventaryCommand];
    
}

- (void)initConnectedReader:(BOOL)isConnected {
    if (isConnected) {
        
        // No information is returned by the reset command
        TSLFactoryDefaultsCommand * resetCommand = [TSLFactoryDefaultsCommand synchronousCommand];
        [_commander executeCommand:resetCommand];
        
        
        _inventaryCommand = [[TSLInventoryCommand alloc] init];
        _inventaryCommand.transponderReceivedDelegate = self;
        _inventaryCommand.captureNonLibraryResponses = YES;
        _inventaryCommand.includeTransponderRSSI = TSL_TriState_YES;
        _inventaryCommand.outputPower = [TSLInventoryCommand maximumOutputPower];
        [_commander addResponder:_inventaryCommand];
        
        
        _readerCommand = [TSLReadTransponderCommand synchronousCommand];
        _readerCommand.includeIndex = TSL_TriState_YES;
        _readerCommand.accessPassword = 0;
        _readerCommand.bank = TSL_DataBank_User;
        _readerCommand.outputPower = [TSLReadTransponderCommand maximumOutputPower];
        [_commander addResponder:_readerCommand];
        
        
        _writeCommand = [TSLWriteTransponderCommand synchronousCommand];
        _writeCommand.outputPower = [TSLWriteTransponderCommand maximumOutputPower];
        [_commander addResponder:_writeCommand];
        
    }
}

NSString *transponderReceivedMsg = @"EPC: ";

- (void)transponderReceived:(NSString *)epc crc:(NSNumber *)crc pc:(NSNumber *)pc rssi:(NSNumber *)rssi fastId:(NSData *)fastId moreAvailable:(BOOL)moreAvailable {
    
    if (moreAvailable) {
        NSString *s = [NSString stringWithFormat:@"%@\n", epc];
        transponderReceivedMsg = [transponderReceivedMsg stringByAppendingString:s];
    } else {
        transponderReceivedMsg = [transponderReceivedMsg stringByAppendingString:epc];
        
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsString:transponderReceivedMsg];
        [pluginResult setKeepCallbackAsBool:TRUE];
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:_scanCallbackId];
        
        transponderReceivedMsg = @"EPC: ";
    }
}




NSString *scanAndReadMsg = @"";

- (void)scanAndRead:(CDVInvokedUrlCommand*)command {
    
    NSString* transponderIdentifier = [command.arguments objectAtIndex:0];
    if (transponderIdentifier.length != 0) {
        _readerCommand.selectBank = TSL_DataBank_ElectronicProductCode;
        _readerCommand.selectData = transponderIdentifier;
        _readerCommand.selectOffset = 32;                                      // This offset is in bits
        _readerCommand.selectLength = (int)transponderIdentifier.length * 4;  // This length is in bits
    }
    
    _readerCommand.transponderDataReceivedBlock = ^(TSLTransponderData * transponder, BOOL moreAvailable)
    {
        if( transponder.epc != nil )
        {
            [_transpondersRead setObject:transponder forKey:transponder.epc];
        }
    };
    
    // Collect the responses in a dictionary
    _transpondersRead = [NSMutableDictionary<NSString *, TSLTransponderData *> dictionary];
    
    // Execute the command
    [_commander executeCommand:_readerCommand];
    
    // Display the data returned
    if( _transpondersRead.count == 0 ) {
        scanAndReadMsg= [scanAndReadMsg stringByAppendingString:@"No transponders responded\n\n"];
    } else {
        scanAndReadMsg = [scanAndReadMsg stringByAppendingString:@"Responses:\n\n"];
        
        // There can be more than one response in the dictionary
        for( TSLTransponderData *transponder in [_transpondersRead objectEnumerator] ) {
            
            scanAndReadMsg = [scanAndReadMsg stringByAppendingFormat:@"EPC: %@\n", transponder.epc];
            scanAndReadMsg = [scanAndReadMsg stringByAppendingFormat:@"Index: %@\n", transponder.index == nil ? @"?" : transponder.index];
            
            // Display the data returned
            if( transponder.readData != nil ) {
                
                if( transponder.readData.length != 0 ) {
                    scanAndReadMsg = [scanAndReadMsg stringByAppendingFormat:@"Data: %@\n\n", [TSLBinaryEncoding asciiStringFromData:transponder.readData]];
                } else {
                    scanAndReadMsg = [scanAndReadMsg stringByAppendingString:@"No data returned\n\n"];
                }
                
            } else {
                NSLog(@"No data for transponder: %@", transponder.epc);
            }
            
            // Report any errors
            if( transponder.accessErrorCode != TSL_TransponderAccessErrorCode_NotSpecified )
            {
                scanAndReadMsg = [scanAndReadMsg stringByAppendingFormat:@"EA: %03d\n%@\n\n",
                                  transponder.accessErrorCode,
                                  [TSLTransponderAccessErrorCode descriptionForTransponderAccessErrorCode: transponder.accessErrorCode]];
            }
            if( transponder.backscatterErrorCode != TSL_TransponderBackscatterErrorCode_NotSpecified )
            {
                scanAndReadMsg = [scanAndReadMsg stringByAppendingFormat:@"EB: %03d\n%@\n\n",
                                  transponder.backscatterErrorCode,
                                  [TSLTransponderBackscatterErrorCode descriptionForTransponderBackscatterErrorCode: transponder.backscatterErrorCode]];
            }
        }
    }
    
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsString:scanAndReadMsg];
    [pluginResult setKeepCallbackAsBool:TRUE];
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
    
    scanAndReadMsg = @"";
    
}


- (void)writeTransponder:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult* pluginResult = nil;
    __block NSString *transponderDetailsMessage = @"";
    
    @try
    {
        
        //
        // Configure the command
        //
        
        // Use the select parameters to write to a single tag
        // Set the match pattern to the full EPC
        NSString* transponderIdentifier = [command.arguments objectAtIndex:0];
        if (transponderIdentifier.length != 0) {
            _writeCommand.selectData = transponderIdentifier;
            _writeCommand.selectLength = (int)transponderIdentifier.length * 4;   // This length is in bits
            _writeCommand.selectBank = TSL_DataBank_ElectronicProductCode;
            
            _writeCommand.selectOffset = 32;                                  // This offset is in bits
        }
        
        
        
        // This demo only works with open tags
        _writeCommand.accessPassword = 0;
        
        
        int transponderBankMemory = [[command.arguments objectAtIndex:1] intValue];
        
        // Set the bank to be used
        _writeCommand.bank = transponderBankMemory;
        
        //        // Set the data to be written
        NSString* data = [command.arguments objectAtIndex:2];
        //        if (data.length % 2 != 0) {
        //            data = [data stringByAppendingString:@"\0"];
        //        }
        
        if (data.length < 64) {
            NSUInteger dif = 64 - data.length;
            for (int i = 0; i < dif; i++) {
                data = [data stringByAppendingString:@"\0"];
            }
        }
        NSData* hexData = [TSLBinaryEncoding dataFromAsciiString:data];
        
        
        _writeCommand.data = hexData;
        
        // Set the locations to write to - this demo writes all the data supplied
        int offset = [[command.arguments objectAtIndex:3] intValue];
        _writeCommand.offset = offset;
        //    int length = [[command.arguments objectAtIndex:4] intValue];
        _writeCommand.length = _writeCommand.data.length / 2;       // This length is in words
        
        
        //
        // Use the TransponderDataReceivedBlock to listen for each transponder - there may be more than one that can match
        // the given EPC - often new tags are supplied with the same EPC
        //
        _writeCommand.transponderDataReceivedBlock = ^(TSLTransponderData * transponder, BOOL moreAvailable)
        {
            if( transponder.epc != nil )
            {
                transponderDetailsMessage = [transponderDetailsMessage stringByAppendingString:
                                             [NSString stringWithFormat:@"%-6s%@\n",
                                              "EPC:", transponder.epc
                                              ]
                                             ];
            }
            if( transponder.wordsWritten != nil )
            {
                transponderDetailsMessage = [transponderDetailsMessage stringByAppendingString:
                                             [NSString stringWithFormat:@"%-16s%@\n",
                                              "Words written:", transponder.wordsWritten
                                              ]
                                             ];
            }
        };
        
        // Execute the command
        [_commander executeCommand:_writeCommand];
        
        // Display the outcome of the
        if( _writeCommand.isSuccessful )
        {
            transponderDetailsMessage = [transponderDetailsMessage stringByAppendingString:@"Data written successfully\n\n"];
        }
        else
        {
            transponderDetailsMessage = [transponderDetailsMessage stringByAppendingString:@"Data write FAILED:\n"];
            for (NSString *msg in _writeCommand.messages)
            {
                transponderDetailsMessage = [transponderDetailsMessage stringByAppendingFormat:@"%@\n", msg];
            }
        }
    }
    
    @catch (NSException *exception)
    {
        transponderDetailsMessage = [transponderDetailsMessage stringByAppendingFormat:@"Exception: %@\n\n", exception.reason];
    }
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                     messageAsString:transponderDetailsMessage];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
    
}

@end
