@objc(RFIDPlugin) class RFIDPlugin : CDVPlugin {
    
    var commander: TSLAsciiCommander = TSLAsciiCommander()
    
    @objc(echo:)
    func echo(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(
            status: CDVCommandStatus_ERROR
        )
        
        let msg = command.arguments[0] as? String ?? ""
        
        if msg.characters.count > 0 {
            let toastController: UIAlertController =
                UIAlertController(
                    title: "",
                    message: msg,
                    preferredStyle: .alert
            )
            
            self.viewController?.present(
                toastController,
                animated: true,
                completion: nil
            )
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                toastController.dismiss(
                    animated: true,
                    completion: nil
                )
            }
            
            pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: msg
            )
        }
        
        self.commandDelegate!.send(
            pluginResult,
            callbackId: command.callbackId
        )
    }
    
    @objc(initPlugin:)
    func initPlugin(command: CDVInvokedUrlCommand) {
        commander.addSynchronousResponder()
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.commanderChangedState(_:)), name: NSNotification.Name.TSLCommanderStateChanged, object: commander)
        
    }
    
    func initConnectedReader(isConnected: Bool) {
        if isConnected {
            let resetCommand = TSLFactoryDefaultsCommand.synchronousCommand()
            commander.execute(resetCommand)
            
            if resetCommand?.isSuccessful ?? false {
                print("Reader reset to Factory Defaults")
            } else {
                print("Unable to reset reader to Factory Defaults")
            }
            
            let versionCommand = TSLVersionInformationCommand.synchronousCommand()
            commander.execute(versionCommand)
            
            let batteryStatus = TSLBatteryStatusCommand.synchronousCommand()
            commander.execute(batteryStatus)
            
            let alert = UIAlertView(title: "Manufacturer: \(versionCommand?.manufacturer)\nSerial Number: \(versionCommand?.serialNumber)\nFirmware: \(versionCommand?.firmwareVersion)\nASCII Protocol: \(versionCommand?.asciiProtocol)\nBattery Level: \(batteryStatus?.batteryLevel)", message: "", delegate: nil, cancelButtonTitle: "OK")
            alert.show()
            
        } else {
            
        }
        
    }
    
    
    
    @objc(getDevices:)
    func getDevices(command: CDVInvokedUrlCommand) {
        
        commander.addSynchronousResponder()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceConnected(_ :)),
                                               name: NSNotification.Name.EAAccessoryDidConnect,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceDisconnected(_ :)),
                                               name: NSNotification.Name.EAAccessoryDidDisconnect,
                                               object: nil)
        
        EAAccessoryManager.shared().registerForLocalNotifications()
        
        EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: nil) { error in
            if error == nil {
                // Inform the user that the device is being connected
                //             _hud = [TSLProgressHUD updateHUD:_hud inView:self.view forBusyState:YES withMessage:@"Waiting for device..."];
            } else {
                var errorMessage: String? = nil
                switch (error as NSError?)?.code {
                case EABluetoothAccessoryPickerError.Code.alreadyConnected.rawValue?:
                    print("AlreadyConnected")
                    errorMessage = "That device is already paired!\n\nTry again and wait a few seconds before choosing. Already paired devices will disappear from the list!"
                case EABluetoothAccessoryPickerError.Code.resultFailed.rawValue?, EABluetoothAccessoryPickerError.Code.resultNotFound.rawValue?:
                    print("NotFound")
                    errorMessage = "Unable to find that device!\n\nEnsure the device is powered on and that the blue LED is flashing."
                case EABluetoothAccessoryPickerError.Code.resultCancelled.rawValue?:
                    print("Cancelled")
                default:
                    break
                }
                
                if (errorMessage != nil) {
                    let alert = UIAlertView(title: "Pairing failed...", message: errorMessage!, delegate: nil, cancelButtonTitle: "OK", otherButtonTitles: "")
                    alert.show()
                }
            }
        }
        
    }
    
    @objc func commanderChangedState(_ notification: NSNotification) {
        let isConnected = notification.userInfo != nil
        
    }
    
    
    @objc func deviceConnected(_ notification: NSNotification) {
        
        if let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory {
            //            commander?.connect(accessory)
            let alert = UIAlertView(title: "Device \(accessory.name) Connected", message: nil, delegate: nil, cancelButtonTitle: "OK")
            alert.show()
            
        }
    }
    
    @objc func deviceDisconnected(_ notification: NSNotification) {
        if let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory {
            let alert = UIAlertView(title: "Device \(accessory.name) Disconnected", message: "", delegate: nil, cancelButtonTitle: "OK")
            alert.show()
        }
    }
    
    
    @objc(disconnectDevice:)
    func disconnectDevice(command: CDVInvokedUrlCommand) {
        if self.commander.isConnected {
            // Stop any synchronous commands and tell the reader to abort
            // This is to leave the reader in the best possible state for other Apps
            defer {
            }
            do {
                
                self.commander.permanentlyDisconnect()
            } catch let exception {
                print("Unable to disconnect: \(exception)")
            }
        }
    }
    
    @objc(getConnectedDeviceData:)
    func getConnectedDeviceData(command: CDVInvokedUrlCommand) {
        //        initScanner()
        let versionCommand = TSLVersionInformationCommand.synchronousCommand()
        let batteryStatus = TSLBatteryStatusCommand.synchronousCommand()
        
        commander.execute(versionCommand)
        commander.execute(batteryStatus)
        
        let alert = UIAlertView(title: "Manufacturer: \(versionCommand?.manufacturer)\nSerial Number: \(versionCommand?.serialNumber)\nFirmware: \(versionCommand?.firmwareVersion)\nASCII Protocol: \(versionCommand?.asciiProtocol)\nBattery Level: \(batteryStatus?.batteryLevel)", message: "", delegate: nil, cancelButtonTitle: "OK")
        alert.show()
    }
}
