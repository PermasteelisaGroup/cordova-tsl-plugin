#import "RFIDPlugin.h"
#import <Cordova/CDV.h>
#import <ExternalAccessory/ExternalAccessory.h>
#import <ExternalAccessory/EAAccessoryManager.h>

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
#import <TSLAsciiCommands/TSLAsciiCommandResponderDelegate.h>

#import <objc/runtime.h>


@interface RFIDPlugin () <TSLInventoryCommandTransponderReceivedDelegate,TSLBarcodeCommandBarcodeReceivedDelegate> {
    
    TSLAsciiCommander *_commander;
    TSLInventoryCommand *_inventoryCommand;
    TSLBarcodeCommand *_barcodeCommand;
    TSLReadTransponderCommand *_readerCommand;
    TSLWriteTransponderCommand *_writeCommand;
    
    NSString *_connectCallbackId;
    NSString *_disconnectCallbackId;
    NSString *_scanCallbackId;
    NSString *_scanBarcodeCallbackId;
    
    NSMutableDictionary<NSString *, TSLTransponderData *> *_transpondersRead;
    NSMutableDictionary<NSString *, TSLTransponderData *> *_transpondersWritten;
    
    NSMutableArray *transpondersScanned;
    NSMutableArray *transpondersLocked;
    NSString *barcodeScanned;
    
    int *inventorySession;
    int *inventoryAlertStatus;
    int *readAlertStatus;
    int *writeAlertStatus;
    
    BOOL isInitialized;
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
    
    inventoryAlertStatus = [[command.arguments objectAtIndex:0] intValue];
    readAlertStatus = [[command.arguments objectAtIndex:1] intValue];
    writeAlertStatus = [[command.arguments objectAtIndex:2] intValue];
    inventorySession = [[command.arguments objectAtIndex:3] intValue];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_accessoryDidConnect:) name:EAAccessoryDidConnectNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_accessoryDidDisconnect:) name:EAAccessoryDidDisconnectNotification object:nil];
    
    
    if(_commander.isConnected)
    {
        // Stop any synchronous commands and tell the reader to abort
        // This is to leave the reader in the best possible state for other Apps
        @try
        {
            [_commander abortSynchronousCommand];
            [_commander executeCommand:[TSLAbortCommand synchronousCommand]];
            [_commander disconnect];
        }
        @catch (NSException *exception)
        {
            NSLog( @"Unable to disconnect when resigningActive: %@", exception.reason);
        }
    }
    
    if (!isInitialized) {
        isInitialized = YES;
        // Listen for accessory connect/disconnects
        [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
        
        _commander = [[TSLAsciiCommander alloc] init];
        // Some synchronous commands will be used in the app
        [_commander addSynchronousResponder];
    }
    
    // Listen for change in TSLAsciiCommander state
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(commanderChangedState:) name:TSLCommanderStateChangedNotification object:_commander];
    
    if( !_commander.isConnected )
    {
        NSArray* connectedAccessories = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
        if (connectedAccessories.count != 0) {
            [_commander connect:[[EAAccessoryManager sharedAccessoryManager] connectedAccessories][0]];
        }

    } else {
        [_commander connect:nil];
    }
    [self initConnectedReader:_commander.isConnected];
    
}



-(void)commanderChangedState:(NSNotification *)notification
{
    // The connected state is indicated by the presence or absence of userInfo
    BOOL isConnected = notification.userInfo != nil;
    
    [self initConnectedReader: isConnected];
}

- (void)initConnectedReader:(BOOL)isConnected {
    if (isConnected) {
        
        // No information is returned by the reset command
        TSLFactoryDefaultsCommand * resetCommand = [TSLFactoryDefaultsCommand synchronousCommand];
        [_commander executeCommand:resetCommand];
        
        
        _inventoryCommand = [[TSLInventoryCommand alloc] init];
        _inventoryCommand.transponderReceivedDelegate = self;
        _inventoryCommand.captureNonLibraryResponses = YES;
        _inventoryCommand.includeTransponderRSSI = TSL_TriState_YES;
        
        if (inventorySession != nil) {
            _inventoryCommand.querySession = inventorySession;
        }
        _inventoryCommand.useAlert = inventoryAlertStatus;
        _inventoryCommand.outputPower = [TSLInventoryCommand maximumOutputPower];
        [_commander addResponder:_inventoryCommand];
        
        _barcodeCommand = [[TSLBarcodeCommand alloc] init];
        _barcodeCommand.barcodeReceivedDelegate = self;
        _barcodeCommand.captureNonLibraryResponses = YES;
        [_commander addResponder:_barcodeCommand];
        
    } else {
        
    }
}


-(void) _accessoryDidConnect:(NSNotification *)notification {
    EAAccessory *connectedAccessory = [[notification userInfo] objectForKey:EAAccessoryKey];
    [_commander connect:connectedAccessory];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:_connectCallbackId];
    
    
}

- (void)_accessoryDidDisconnect:(NSNotification *)notification {
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:_disconnectCallbackId];
}


- (void)getDevices:(CDVInvokedUrlCommand*)command {
    
    [[EAAccessoryManager sharedAccessoryManager] showBluetoothAccessoryPickerWithNameFilter:nil completion:^(NSError *error) {
        if( error == nil )
        {
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
                    break;
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
                                                      otherButtonTitles:nil];
                [alert show];
            }
        }
    }];
}

- (void)disconnectDevice:(CDVInvokedUrlCommand*)command {
    if (_commander.isConnected) {
        [_commander permanentlyDisconnect];
        
        _disconnectCallbackId = command.callbackId;
    } else {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                          messageAsString:[self jsonWithErrorMsg: @"Reader not connected"]];
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }
}

- (void)getConnectedDeviceData:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult* pluginResult = nil;
    
    @try {
        TSLVersionInformationCommand *versionCommand = [TSLVersionInformationCommand synchronousCommand];
        [_commander executeCommand:versionCommand];
        TSLBatteryStatusCommand *batteryCommand = [TSLBatteryStatusCommand synchronousCommand];
        [_commander executeCommand:batteryCommand];
        
        NSMutableDictionary *deviceInfoDictionary = [[NSMutableDictionary alloc] init];
        [deviceInfoDictionary setObject:[self dictionaryWithPropertiesOfObject:versionCommand] forKey:@"deviceVersion"];
        [deviceInfoDictionary setObject:[self dictionaryWithPropertiesOfObject:batteryCommand] forKey:@"battery"];
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                         messageAsString:[self jsonFromDictionary: deviceInfoDictionary]];
        
    }
    @catch (NSException *exception)
    {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:[self jsonWithErrorMsg: exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
    
}


- (void)scan:(CDVInvokedUrlCommand*)command {
    if (_commander.isConnected) {
        _scanCallbackId = command.callbackId;
        
        [_commander executeCommand:_inventoryCommand];
    } else {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                          messageAsString:[self jsonWithErrorMsg: @"Reader not connected"]];
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }
}




- (void)transponderReceived:(NSString *)epc crc:(NSNumber *)crc pc:(NSNumber *)pc rssi:(NSNumber *)rssi fastId:(NSData *)fastId moreAvailable:(BOOL)moreAvailable {
    if (transpondersScanned == nil) {
        transpondersScanned = [[NSMutableArray alloc] init];
    }
    
    [transpondersScanned addObject:epc];
    
    if (!moreAvailable) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsString:[self jsonFromArray:@"epc" array:transpondersScanned]];
        [pluginResult setKeepCallbackAsBool:TRUE];
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:_scanCallbackId];
        
        transpondersScanned = [[NSMutableArray alloc] init];
        
    }
}
- (void)barcodeReceived:(NSString *)barcode{
    if (barcodeScanned == nil) {
        barcodeScanned = [[NSString alloc] init];
    }
    
    barcodeScanned = barcode;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsString:[self jsonWithMessage:@"value":barcodeScanned]];
    [pluginResult setKeepCallbackAsBool:TRUE];
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:_scanBarcodeCallbackId];
    
    barcodeScanned = [[NSString alloc] init];


}

- (void)scanAndRead:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult* pluginResult = nil;
    
    @try {
        
        NSString* transponderIdentifier = [command.arguments objectAtIndex:0];
        int transponderBankMemory = [[command.arguments objectAtIndex:1] intValue];
        BOOL isEPCRead = [[command.arguments objectAtIndex:2] boolValue];
        BOOL isPasswordRead = [[command.arguments objectAtIndex:3] boolValue];
        NSString* accessPassword = [command.arguments objectAtIndex:4];
        int epcMemoryLength = [[command.arguments objectAtIndex:5] intValue];
        int userMemoryLength = [[command.arguments objectAtIndex:6] intValue];
        
        _readerCommand = [TSLReadTransponderCommand synchronousCommand];
        _readerCommand.useAlert = readAlertStatus;
        _readerCommand.includeIndex = TSL_TriState_YES;
        _readerCommand.outputPower = [TSLReadTransponderCommand maximumOutputPower];
        [_commander addResponder:_readerCommand];
        
        _readerCommand.resetParameters = TSL_TriState_YES;
        
        if (accessPassword.length != 0) {
            _readerCommand.accessPassword = accessPassword;
        } else {
            _readerCommand.accessPassword = 0;
        }
        
        _readerCommand.bank = transponderBankMemory;
        
        if (transponderBankMemory == TSL_DataBank_ElectronicProductCode) {
            if (isEPCRead) {
                _readerCommand.offset = 2;
                _readerCommand.length = epcMemoryLength/16;
            } else {
                _readerCommand.offset = 1;
                _readerCommand.length = 1;
            }
        } else if (transponderBankMemory == TSL_DataBank_TransponderIdentifier) {
            _readerCommand.offset = 0;
            _readerCommand.length = 8;
        } else if (transponderBankMemory == TSL_DataBank_User) {
            _readerCommand.offset = 0;
            _readerCommand.length = userMemoryLength/16;
        } else if (transponderBankMemory == TSL_DataBank_Reserved) {
            if (isPasswordRead) {
                _readerCommand.offset = 2;
                _readerCommand.length = 2;
            } else {
                _readerCommand.offset = 0;
                _readerCommand.length = 2;
            }
        }
        
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
        
        
        NSMutableArray *transpondersArray = [NSMutableArray new];
        
        for( TSLTransponderData *transponder in [_transpondersRead objectEnumerator] )
        {
            NSDictionary *readDataDictionary = @{};
            if (transponder.readData != nil) {
                readDataDictionary = @{
                                       @"hex" : [TSLBinaryEncoding toBase16String:transponder.readData],
                                       @"ascii" : [TSLBinaryEncoding asciiStringFromData:transponder.readData]
                                       };
            }
            NSDictionary *transponderDict = @{
                                              @"epc" : transponder.epc,
                                              @"index" : transponder.index,
                                              @"data" : readDataDictionary,
                                              @"accessError" : [TSLTransponderAccessErrorCode descriptionForTransponderAccessErrorCode: transponder.accessErrorCode],
                                              @"backscatterError" : [TSLTransponderBackscatterErrorCode descriptionForTransponderBackscatterErrorCode: transponder.backscatterErrorCode],
                                              @"accessErrorCode" : [NSNumber numberWithInt:transponder.accessErrorCode],
                                              @"backscatterErrorCode" : [NSNumber numberWithInt:transponder.backscatterErrorCode]
                                              };
            [transpondersArray addObject:transponderDict];
        }
        
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                         messageAsString:[self jsonFromArray:@"transponders" array:transpondersArray]];
        [pluginResult setKeepCallbackAsBool:TRUE];
        
    }
    @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:[self jsonWithErrorMsg:exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
    
}

- (void)writeTransponder:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult* pluginResult = nil;
    
    @try
    {
        
        NSString* transponderIdentifier = [command.arguments objectAtIndex:0];
        int transponderBankMemory = [[command.arguments objectAtIndex:1] intValue];
        NSString* data = [command.arguments objectAtIndex:2];
        BOOL isEPCWrite = [[command.arguments objectAtIndex:3] boolValue];
        BOOL isPasswordWrite = [[command.arguments objectAtIndex:4] boolValue];
        NSString* accessPassword = [command.arguments objectAtIndex:5];
        int epcMemoryLength = [[command.arguments objectAtIndex:6] intValue];
        int userMemoryLength = [[command.arguments objectAtIndex:7] intValue];
        
        _writeCommand = [TSLWriteTransponderCommand synchronousCommand];
        _writeCommand.useAlert = writeAlertStatus;
        _writeCommand.outputPower = [TSLWriteTransponderCommand maximumOutputPower];
        _writeCommand.includeIndex = TSL_TriState_YES;
        [_commander addResponder:_writeCommand];
        
        _writeCommand.resetParameters = TSL_TriState_YES;
        // Use the select parameters to write to a single tag
        // Set the match pattern to the full EPC
        if (transponderIdentifier.length != 0) {
            _writeCommand.selectBank = TSL_DataBank_ElectronicProductCode;
            _writeCommand.selectData = transponderIdentifier;
            _writeCommand.selectOffset = 32;                                  // This offset is in bits
            _writeCommand.selectLength = (int)transponderIdentifier.length * 4;   // This length is in bits
        }
        
        if (accessPassword.length != 0) {
            _writeCommand.accessPassword = accessPassword;
        } else {
            _writeCommand.accessPassword = 0;
        }
        
        // Set the bank to be used
        _writeCommand.bank = transponderBankMemory;
        
        if (transponderBankMemory == TSL_DataBank_ElectronicProductCode) {
            if (isEPCWrite) {
                int epcMaxAsciiCharacters = epcMemoryLength/8;
                if (data.length < epcMaxAsciiCharacters) {
                    NSUInteger dif = epcMaxAsciiCharacters - data.length;
                    for (int i = 0; i < dif; i++) {
                        data = [data stringByAppendingString:@"\0"];
                    }
                }
                NSData* hexData = [TSLBinaryEncoding dataFromAsciiString:data];
                
                // Set the data to be written
                _writeCommand.data = hexData;
                
                // Set the locations to write to - this demo writes all the data supplied
                _writeCommand.offset = 2;
                _writeCommand.length = (int)_writeCommand.data.length / 2;       // This length is in words
                
            } else {
                NSData* hexData = [TSLBinaryEncoding fromBase16String:data];
                
                _writeCommand.data = hexData;
                _writeCommand.offset = 1;
                _writeCommand.length = 1;
            }
        } else if (transponderBankMemory == TSL_DataBank_TransponderIdentifier) {
            return;
        } else if (transponderBankMemory == TSL_DataBank_User) {
            int userMemoryMaxAsciiCharacters = userMemoryLength/8;
            if (data.length < userMemoryMaxAsciiCharacters) {
                NSUInteger dif = userMemoryMaxAsciiCharacters - data.length;
                for (int i = 0; i < dif; i++) {
                    data = [data stringByAppendingString:@"\0"];
                }
            }
            NSData* hexData = [TSLBinaryEncoding dataFromAsciiString:data];
            
            // Set the data to be written
            _writeCommand.data = hexData;
            
            // Set the locations to write to - this demo writes all the data supplied
            _writeCommand.offset = 0;
            _writeCommand.length = (int)_writeCommand.data.length/2;       // This length is in words
            
        } else if (transponderBankMemory == TSL_DataBank_Reserved) {
            _writeCommand.data = [TSLBinaryEncoding fromBase16String:data];
            if (isPasswordWrite) {
                _writeCommand.offset = 2;
                _writeCommand.length = 2;
            } else {
                _writeCommand.offset = 0;
                _writeCommand.length = 2;
            }
        }
        
        //
        // Use the TransponderDataReceivedBlock to listen for each transponder - there may be more than one that can match
        // the given EPC - often new tags are supplied with the same EPC
        //
        _writeCommand.transponderDataReceivedBlock = ^(TSLTransponderData * transponder, BOOL moreAvailable)
        {
            if( transponder.epc != nil )
            {
                [_transpondersWritten setObject:transponder forKey:transponder.epc];
            }
        };
        
        // Collect the responses in a dictionary
        _transpondersWritten = [NSMutableDictionary<NSString *, TSLTransponderData *> dictionary];
        
        // Execute the command
        [_commander executeCommand:_writeCommand];
        
        NSMutableArray *transpondersArray = [NSMutableArray new];
        
        for( TSLTransponderData *transponder in [_transpondersWritten objectEnumerator] )
        {
            NSDictionary *transponderDict = @{
                                              @"epc" : transponder.epc,
                                              @"index" : transponder.index,
                                              @"accessError" : [TSLTransponderAccessErrorCode descriptionForTransponderAccessErrorCode: transponder.accessErrorCode],
                                              @"backscatterError" : [TSLTransponderBackscatterErrorCode descriptionForTransponderBackscatterErrorCode: transponder.backscatterErrorCode],
                                              @"wordsWritten" : transponder.wordsWritten,
                                              @"accessErrorCode" : [NSNumber numberWithInt:transponder.accessErrorCode],
                                              @"backscatterErrorCode" : [NSNumber numberWithInt:transponder.backscatterErrorCode]
                                              };
            [transpondersArray addObject:transponderDict];
        }
        
        if (_writeCommand.isSuccessful) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsString:[self jsonFromArray:@"transponders" array:transpondersArray]];
            
        } else {
            for (NSString *msg in _writeCommand.messages) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsString:[self jsonWithErrorMsg:msg]];
            }
        }
    }
    
    @catch (NSException *exception)
    {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:[self jsonWithErrorMsg:exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
    
}




- (void)lock:(CDVInvokedUrlCommand*)command {
    
    @try {
        
        TSLLockCommand *lockCommand = [TSLLockCommand synchronousCommand];
        
        NSString* transponderIdentifier = [command.arguments objectAtIndex:0];
        NSString* lockPayload = [command.arguments objectAtIndex:1];
        NSString* accessPassword = [command.arguments objectAtIndex:2];
        
        if (transponderIdentifier.length != 0) {
            lockCommand.selectBank = TSL_DataBank_ElectronicProductCode;
            lockCommand.selectData = transponderIdentifier;
            lockCommand.selectOffset = 32;                                  // This offset is in bits
            lockCommand.selectLength = (int)transponderIdentifier.length * 4;   // This length is in bits
        }
        lockCommand.lockPayload = lockPayload;
        lockCommand.accessPassword = accessPassword;
        
        lockCommand.transponderDataReceivedBlock = ^(TSLTransponderData * transponder, BOOL moreAvailable)
        {
            if (transpondersLocked == nil) {
                transpondersLocked = [[NSMutableArray alloc] init];
            }
            
            if (transponder.didLock) {
                [transpondersLocked addObject:transponder.epc];
            }
            
            if (!moreAvailable) {
                CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                  messageAsString:[self jsonFromArray:@"epc" array:transpondersLocked]];
                [pluginResult setKeepCallbackAsBool:TRUE];
                [self.commandDelegate sendPluginResult:pluginResult
                                            callbackId:command.callbackId];
                
                transpondersLocked = [[NSMutableArray alloc] init];
                
            }
        };
        
        // Execute the command
        [_commander executeCommand:lockCommand];
        
    }
    
    @catch (NSException *exception) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                          messageAsString:[self jsonWithErrorMsg:exception.reason]];
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }
}







- (void)customScanAndRead:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult* pluginResult = nil;
    
    @try {
        
        NSString* transponderIdentifier = [command.arguments objectAtIndex:0];
        int transponderBankMemory = [[command.arguments objectAtIndex:1] intValue];
        int offset = [[command.arguments objectAtIndex:2] intValue];
        int lenght = [[command.arguments objectAtIndex:3] intValue];
        NSString* accessPassword = [command.arguments objectAtIndex:4];
        
        
        _readerCommand = [TSLReadTransponderCommand synchronousCommand];
        _readerCommand.useAlert = readAlertStatus;
        _readerCommand.includeIndex = TSL_TriState_YES;
        _readerCommand.outputPower = [TSLReadTransponderCommand maximumOutputPower];
        [_commander addResponder:_readerCommand];
        
        _readerCommand.resetParameters = TSL_TriState_YES;
        
        if (accessPassword.length != 0) {
            _readerCommand.accessPassword = accessPassword;
        } else {
            _readerCommand.accessPassword = 0;
        }
        
        _readerCommand.bank = transponderBankMemory;
        _readerCommand.offset = offset;
        _readerCommand.length = lenght;
        
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
        
        
        NSMutableArray *transpondersArray = [NSMutableArray new];
        
        for( TSLTransponderData *transponder in [_transpondersRead objectEnumerator] )
        {
            NSDictionary *readDataDictionary = @{};
            if (transponder.readData != nil) {
                readDataDictionary = @{
                                       @"hex" : [TSLBinaryEncoding toBase16String:transponder.readData],
                                       @"ascii" : [TSLBinaryEncoding asciiStringFromData:transponder.readData]
                                       };
            }
            NSDictionary *transponderDict = @{
                                              @"epc" : transponder.epc,
                                              @"index" : transponder.index,
                                              @"data" : readDataDictionary,
                                              @"accessError" : [TSLTransponderAccessErrorCode descriptionForTransponderAccessErrorCode: transponder.accessErrorCode],
                                              @"backscatterError" : [TSLTransponderBackscatterErrorCode descriptionForTransponderBackscatterErrorCode: transponder.backscatterErrorCode],
                                              @"accessErrorCode" : [NSNumber numberWithInt:transponder.accessErrorCode],
                                              @"backscatterErrorCode" : [NSNumber numberWithInt:transponder.backscatterErrorCode]
                                              };
            [transpondersArray addObject:transponderDict];
        }
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                         messageAsString:[self jsonFromArray:@"transponders" array:transpondersArray]];
        [pluginResult setKeepCallbackAsBool:TRUE];
        
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:[self jsonWithErrorMsg:exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
    
}



- (void)customWriteTransponder:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult* pluginResult = nil;
    
    @try {
        
        NSString* transponderIdentifier = [command.arguments objectAtIndex:0];
        int transponderBankMemory = [[command.arguments objectAtIndex:1] intValue];
        NSString* data = [command.arguments objectAtIndex:2];
        int offset = [[command.arguments objectAtIndex:3] intValue];
        NSString* accessPassword = [command.arguments objectAtIndex:4];
        
        _writeCommand = [TSLWriteTransponderCommand synchronousCommand];
        _writeCommand.useAlert = writeAlertStatus;
        _writeCommand.outputPower = [TSLWriteTransponderCommand maximumOutputPower];
        _writeCommand.includeIndex = TSL_TriState_YES;
        [_commander addResponder:_writeCommand];
        
        _writeCommand.resetParameters = TSL_TriState_YES;
        
        if (transponderIdentifier.length != 0) {
            _writeCommand.selectData = transponderIdentifier;
            _writeCommand.selectLength = (int)transponderIdentifier.length * 4;   // This length is in bits
            _writeCommand.selectBank = TSL_DataBank_ElectronicProductCode;
            _writeCommand.selectOffset = 32;                                  // This offset is in bits
        }
        
        if (accessPassword.length != 0) {
            _writeCommand.accessPassword = accessPassword;
        } else {
            _writeCommand.accessPassword = 0;
        }
        
        // Set the bank to be used
        _writeCommand.bank = transponderBankMemory;
        
        NSData* hexData = [TSLBinaryEncoding dataFromAsciiString:data];
        _writeCommand.data = hexData;
        _writeCommand.offset = offset;
        _writeCommand.length = (int)_writeCommand.data.length / 2;
        
        
        _writeCommand.transponderDataReceivedBlock = ^(TSLTransponderData * transponder, BOOL moreAvailable)
        {
            if( transponder.epc != nil )
            {
                [_transpondersWritten setObject:transponder forKey:transponder.epc];
            }
        };
        
        // Collect the responses in a dictionary
        _transpondersWritten = [NSMutableDictionary<NSString *, TSLTransponderData *> dictionary];
        
        // Execute the command
        [_commander executeCommand:_writeCommand];
        
        NSMutableArray *transpondersArray = [NSMutableArray new];
        
        for( TSLTransponderData *transponder in [_transpondersWritten objectEnumerator] )
        {
            NSDictionary *transponderDict = @{
                                              @"epc" : transponder.epc,
                                              @"index" : transponder.index,
                                              @"wordsWritten" : transponder.wordsWritten,
                                              @"accessError" : [TSLTransponderAccessErrorCode descriptionForTransponderAccessErrorCode: transponder.accessErrorCode],
                                              @"backscatterError" : [TSLTransponderBackscatterErrorCode descriptionForTransponderBackscatterErrorCode: transponder.backscatterErrorCode],
                                              @"accessErrorCode" : [NSNumber numberWithInt:transponder.accessErrorCode],
                                              @"backscatterErrorCode" : [NSNumber numberWithInt:transponder.backscatterErrorCode]
                                              };
            [transpondersArray addObject:transponderDict];
        }
        
        if (_writeCommand.isSuccessful) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsString:[self jsonFromArray:@"transponders" array:transpondersArray]];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                             messageAsString:[self jsonWithErrorMsg:@"Data write FAILED"]];
        }
    }
    
    @catch (NSException *exception)
    {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:[self jsonWithErrorMsg:exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
    
}




- (void) barcodeScan:(CDVInvokedUrlCommand*)command{
    
    if (_commander.isConnected) {
        _scanBarcodeCallbackId = command.callbackId;
        
        [_commander executeCommand:_barcodeCommand];
    } else {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                          messageAsString:[self jsonWithErrorMsg: @"Reader not connected"]];
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }
}


- (void)alert:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult* pluginResult = nil;
    @try {
        TSLAlertCommand *alertCommand = [TSLAlertCommand synchronousCommand];
        
        int duration = [[command.arguments objectAtIndex:0] intValue];
        int enableBuzzer= [[command.arguments objectAtIndex:1] intValue];
        int enableVibrator = [[command.arguments objectAtIndex:2] intValue];
        int tone = [[command.arguments objectAtIndex:3] intValue];
        
        alertCommand.duration = duration;
        alertCommand.enableBuzzer = enableBuzzer;
        alertCommand.enableVibrator = enableVibrator;
        alertCommand.tone = tone;
        
        [_commander executeCommand:alertCommand];
        
        // No information is returned by the reset command
        TSLFactoryDefaultsCommand * resetCommand = [TSLFactoryDefaultsCommand synchronousCommand];
        [_commander executeCommand:resetCommand];
    }
    
    @catch (NSException *exception)
    {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:[self jsonWithErrorMsg:exception.reason]];
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }
}

- (void)changeInventorySession:(CDVInvokedUrlCommand*)command {
    int querySession = [[command.arguments objectAtIndex:0] intValue];
    _inventoryCommand.querySession = querySession;
    [_commander executeCommand:_inventoryCommand];
}


- (void)changeVibrationForCommand:(CDVInvokedUrlCommand*)command {
    int commandSelected = [[command.arguments objectAtIndex:0] intValue];
    int status = [[command.arguments objectAtIndex:1] intValue];
    if (commandSelected == 0) {
        _inventoryCommand.useAlert = status;
        [_commander executeCommand:_inventoryCommand];
    } else if (commandSelected == 1) {
        readAlertStatus = status;
    } else if (commandSelected == 2) {
        writeAlertStatus = status;
    }
}






- (NSString*) jsonFromObject:(id)object  {
    NSError *error = nil;
    NSData *json;
    
    NSDictionary *dict = [self dictionaryWithPropertiesOfObject:object];
    // Dictionary convertable to JSON ?
    if ([NSJSONSerialization isValidJSONObject:dict])
    {
        // Serialize the dictionary
        json = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
        
        // If no errors, let's view the JSON
        if (json != nil && error == nil)
        {
            NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
            
            NSLog(@"JSON: %@", jsonString);
            return jsonString;
        }
    }
    
    return @"";
    
}


//Add this utility method in your class.
- (NSDictionary *) dictionaryWithPropertiesOfObject:(id)obj
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    unsigned count;
    objc_property_t *properties = class_copyPropertyList([obj class], &count);
    
    for (int i = 0; i < count; i++) {
        NSString *key = [NSString stringWithUTF8String:property_getName(properties[i])];
        [dict setObject:[obj valueForKey:key] ?: [NSNull null] forKey:key];
    }
    
    free(properties);
    return [NSDictionary dictionaryWithDictionary:dict];
}




- (NSString*) jsonFromArray:(NSString*)key array:(NSArray*)array  {
    // Dictionary with several kay/value pairs and the above array of arrays
    NSDictionary *dict = @{key : array};
    
    NSError *error = nil;
    NSData *json;
    
    // Dictionary convertable to JSON ?
    if ([NSJSONSerialization isValidJSONObject:dict])
    {
        // Serialize the dictionary
        json = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
        
        // If no errors, let's view the JSON
        if (json != nil && error == nil)
        {
            NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
            
            NSLog(@"JSON: %@", jsonString);
            return jsonString;
        }
    }
    return @"";
}


- (NSString*) jsonFromDictionary:(NSDictionary*)dictionary  {
    
    NSError *error = nil;
    NSData *json;
    
    // Dictionary convertable to JSON ?
    if ([NSJSONSerialization isValidJSONObject:dictionary])
    {
        // Serialize the dictionary
        json = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:&error];
        
        // If no errors, let's view the JSON
        if (json != nil && error == nil)
        {
            NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
            
            NSLog(@"JSON: %@", jsonString);
            return jsonString;
        }
    }
    return @"";
}



- (NSString*) jsonStringFromDict:(NSDictionary*)dictionary  {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary
                                                       options:NSJSONWritingPrettyPrinted // Pass 0 if you don't care about the readability of the generated string
                                                         error:&error];
    
    if (! jsonData) {
        NSLog(@"Got an error: %@", error);
    } else {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        return jsonString;
    }
    return @"";
}





- (NSDictionary*) dictionaryFromObject:(id)object  {
    
    NSDictionary *dict = [self dictionaryWithPropertiesOfObject:object];
    return dict;
    
}


- (NSString*) jsonWithErrorMsg:(NSString*)msg  {
    
    NSDictionary *dict = @{@"msg" : msg};
    
    NSError *error = nil;
    NSData *json;
    
    // Dictionary convertable to JSON ?
    if ([NSJSONSerialization isValidJSONObject:dict])
    {
        // Serialize the dictionary
        json = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
        
        // If no errors, let's view the JSON
        if (json != nil && error == nil)
        {
            NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
            
            NSLog(@"JSON: %@", jsonString);
            return jsonString;
        }
    }
    return @"";
}

- (NSString*) jsonWithMessage:(NSString*)key :(NSString*)value  {
    
    NSDictionary *dict = @{key : value};
    
    NSError *error = nil;
    NSData *json;
    
    // Dictionary convertable to JSON ?
    if ([NSJSONSerialization isValidJSONObject:dict])
    {
        // Serialize the dictionary
        json = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
        
        // If no errors, let's view the JSON
        if (json != nil && error == nil)
        {
            NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
            
            NSLog(@"JSON: %@", jsonString);
            return jsonString;
        }
    }
    return @"";
}

@end



