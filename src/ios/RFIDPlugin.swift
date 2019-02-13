@objc(RFIDPlugin) class RFIDPlugin : CDVPlugin {
    
    var commander: TSLAsciiCommander = TSLAsciiCommander()
    var inventaryCommand = TSLInventoryCommand()
    
    @objc(initPlugin:)
    func initPlugin(command: CDVInvokedUrlCommand) {
        
        commander = TSLAsciiCommander()
        commander.addSynchronousResponder()
        
        commander.connect(nil)
        
        EAAccessoryManager.shared().registerForLocalNotifications()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceConnected(_ :)),
                                               name: NSNotification.Name.EAAccessoryDidConnect,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceDisconnected(_ :)),
                                               name: NSNotification.Name.EAAccessoryDidDisconnect,
                                               object: nil)
        
    }
    
    
    @objc(getDevices:)
    func getDevices(command: CDVInvokedUrlCommand) {
        
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
    
    
    @objc func deviceConnected(_ notification: NSNotification) {
        
        if let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory {
            commander.connect(accessory)
            //            commander.connectedAccessory = accessory
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
        let versionCommand = TSLVersionInformationCommand.synchronousCommand()
        let batteryStatus = TSLBatteryStatusCommand.synchronousCommand()
        
        commander.execute(versionCommand)
        commander.execute(batteryStatus)
        
        let alert = UIAlertView(title: "Manufacturer: \(versionCommand?.manufacturer)\nSerial Number: \(versionCommand?.serialNumber)\nFirmware: \(versionCommand?.firmwareVersion)\nASCII Protocol: \(versionCommand?.asciiProtocol)\nBattery Level: \(batteryStatus?.batteryLevel)", message: "", delegate: nil, cancelButtonTitle: "OK")
        alert.show()
    }
}
